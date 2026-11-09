# CalculiX managed updater for MultiSuite (Windows PowerShell 5.1+)
# Manifest JSON example: {"version":"2.xx","url":"https://trusted.example/ccx.zip","sha256":"64 hex chars","executable":"bin/ccx.exe"}
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][ValidateSet('Status','Install','Rollback')][string]$Action,
  [string]$ManifestPath,
  [string]$Root = (Join-Path $env:LOCALAPPDATA 'MultiSuite\solvers\calculix')
)
$ErrorActionPreference = 'Stop'
function Log([string]$message) {
  if (!(Test-Path $Root)) { New-Item -ItemType Directory -Force -Path $Root | Out-Null }
  Add-Content -LiteralPath (Join-Path $Root 'update.log') -Value ("{0:o} {1}" -f (Get-Date),$message)
}
function Set-Active([string]$target) {
  $tmp = Join-Path $Root 'active.tmp'
  Set-Content -LiteralPath $tmp -Value $target -Encoding UTF8
  Move-Item -LiteralPath $tmp -Destination (Join-Path $Root 'active.txt') -Force
}
New-Item -ItemType Directory -Force -Path $Root | Out-Null
$active = Join-Path $Root 'active.txt'
$previous = Join-Path $Root 'previous.txt'
if ($Action -eq 'Status') {
  if (Test-Path $active) { $exe=(Get-Content $active -Raw).Trim(); Write-Output "Active: $exe"; if (!(Test-Path $exe)) { exit 2 } }
  else { Write-Output 'No managed CalculiX installed' }
  exit 0
}
if ($Action -eq 'Rollback') {
  if (!(Test-Path $previous)) { throw 'No previous version available' }
  $exe = (Get-Content $previous -Raw).Trim()
  if (!(Test-Path $exe)) { throw 'Previous executable missing' }
  Set-Active $exe
  Log "Rollback to $exe"
  Write-Output "Rolled back to $exe"
  exit 0
}
if (!$ManifestPath -or !(Test-Path $ManifestPath)) { throw 'A trusted local manifest is required' }
$m = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
if ([string]::IsNullOrWhiteSpace($m.version) -or $m.version -notmatch '^[A-Za-z0-9._-]+$') { throw 'Invalid version' }
if ($m.sha256 -notmatch '^[a-fA-F0-9]{64}$') { throw 'SHA256 required' }
$uri = [Uri]$m.url
if ($uri.Scheme -ne 'https') { throw 'HTTPS required' }
$rel = [string]$m.executable
if (!$rel -or [IO.Path]::IsPathRooted($rel) -or $rel -match '(^|[\\/])\.\.([\\/]|$)') { throw 'Invalid executable path' }
$destination = Join-Path $Root ('versions\' + $m.version)
$exe = Join-Path $destination $rel
if (Test-Path $exe) { Write-Output "Already installed: $exe"; exit 0 }
$work = Join-Path $Root ('staging-' + [guid]::NewGuid().ToString('N'))
$zip = Join-Path $work 'package.zip'
try {
  New-Item -ItemType Directory -Force -Path $work | Out-Null
  Log "Downloading $($m.version) from $($uri.Host)"
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  Invoke-WebRequest -Uri $uri.AbsoluteUri -OutFile $zip -UseBasicParsing -TimeoutSec 180
  $hash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash
  if ($hash -ine $m.sha256) { throw 'SHA256 mismatch' }
  $extract = Join-Path $work 'extracted'
  Expand-Archive -LiteralPath $zip -DestinationPath $extract
  $candidate = Join-Path $extract $rel
  if (!(Test-Path $candidate)) { throw 'CalculiX executable missing from package' }
  if (Test-Path $destination) { throw 'Version directory already exists' }
  Move-Item -LiteralPath $extract -Destination $destination
  if (Test-Path $active) { Copy-Item -LiteralPath $active -Destination $previous -Force }
  Set-Active $exe
  Log "Activated $($m.version) SHA256=$hash"
  Write-Output "Installed: $exe"
} catch {
  Log "FAILED: $($_.Exception.Message)"
  throw
} finally {
  if (Test-Path $work) { Remove-Item -LiteralPath $work -Recurse -Force }
}

#requires -Version 5.1
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][ValidateSet('Status','Install','Rollback','Catalog')][string]$Action,
  [string]$ManifestPath,
  [string]$Version,
  [string]$CatalogPath = (Join-Path $PSScriptRoot 'calculix_catalog.json'),
  [string]$Root = (Join-Path $env:LOCALAPPDATA 'MultiSuite\solvers\calculix'),
  [ValidateRange(1,600)][int]$TestTimeoutSec = 60
)
$ErrorActionPreference = 'Stop'
$Root = [IO.Path]::GetFullPath($Root)
New-Item -ItemType Directory -Force -Path $Root | Out-Null
$active = Join-Path $Root 'active.txt'
$previous = Join-Path $Root 'previous.txt'
function Log([string]$message) {
  Add-Content -LiteralPath (Join-Path $Root 'update.log') -Value ("{0:o} {1}" -f (Get-Date),$message)
}
function Write-Pointer([string]$path, [string]$target) {
  $tmp = $path + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
  $backup = $tmp + '.bak'
  try {
    [IO.File]::WriteAllText($tmp, $target, (New-Object Text.UTF8Encoding($false)))
    if (Test-Path -LiteralPath $path) { [IO.File]::Replace($tmp, $path, $backup) }
    else { [IO.File]::Move($tmp, $path) }
  } finally {
    foreach ($temporary in @($tmp,$backup)) {
      if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
    }
  }
}
function Child-Path([string]$base, [string]$relative) {
  if (!$relative -or [IO.Path]::IsPathRooted($relative) -or $relative -match '(^|[\\/])\.\.([\\/]|$)|:|[\x00-\x1f]') { throw 'Invalid package path' }
  $base = [IO.Path]::GetFullPath($base).TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar
  $target = [IO.Path]::GetFullPath((Join-Path $base $relative))
  if (!$target.StartsWith($base, [StringComparison]::OrdinalIgnoreCase)) { throw 'Package path outside root' }
  return $target
}
function Read-Managed([string]$path) {
  if (!(Test-Path -LiteralPath $path)) { return $null }
  $candidate = (Get-Content -LiteralPath $path -Raw).Trim()
  $base = [IO.Path]::GetFullPath((Join-Path $Root 'versions')).TrimEnd('\') + '\'
  if (![IO.Path]::IsPathRooted($candidate) -or !([IO.Path]::GetFullPath($candidate)).StartsWith($base,[StringComparison]::OrdinalIgnoreCase)) { throw 'Pointer outside managed versions' }
  if (!(Test-Path -LiteralPath $candidate -PathType Leaf)) { throw 'Managed executable missing' }
  return $candidate
}
function Activate-Version([string]$target, [string]$old) {
  $hadPrevious = Test-Path -LiteralPath $previous
  $oldPrevious = if ($hadPrevious) { [IO.File]::ReadAllText($previous) } else { $null }
  if ($old) { Write-Pointer $previous $old }
  try { Write-Pointer $active $target }
  catch {
    if ($old) {
      if ($hadPrevious) { Write-Pointer $previous $oldPrevious }
      elseif (Test-Path -LiteralPath $previous) { Remove-Item -LiteralPath $previous -Force }
    }
    throw
  }
}
function Test-Solver([string]$exe) {
  # Tetraedro unitario, E=1000 Pa, nu=0.3, F_x=1 N no no 2.
  # Demais graus presos: u2x=6*(1+nu)*(1-2nu)/(E*(1-nu)).
  $testDir = Join-Path $Root ('smoke-' + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $testDir | Out-Null
  $deck = @'
*HEADING
MultiPhysics CalculiX installation benchmark (SI)
*NODE, NSET=ALL
1,0,0,0
2,1,0,0
3,0,1,0
4,0,0,1
*ELEMENT,TYPE=C3D4,ELSET=SOLID
1,1,2,3,4
*MATERIAL,NAME=MAT
*ELASTIC
1000,0.3
*SOLID SECTION,ELSET=SOLID,MATERIAL=MAT
*NSET,NSET=TIP
2
*BOUNDARY
ALL,2,3
1,1,1
3,1,1
4,1,1
*STEP
*STATIC
*CLOAD
2,1,1
*NODE PRINT,NSET=TIP
U
*END STEP
'@
  $process = $null
  try {
    [IO.File]::WriteAllText((Join-Path $testDir 'smoke.inp'), $deck, [Text.Encoding]::ASCII)
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $exe; $info.Arguments = '-i smoke'; $info.WorkingDirectory = $testDir
    $info.UseShellExecute = $false; $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true; $info.RedirectStandardError = $true
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $info
    [void]$process.Start()
    $stdout = $process.StandardOutput.ReadToEndAsync(); $stderr = $process.StandardError.ReadToEndAsync()
    if (!$process.WaitForExit($TestTimeoutSec * 1000)) { $process.Kill(); $process.WaitForExit(); throw 'CalculiX benchmark timeout' }
    [IO.File]::WriteAllText((Join-Path $Root 'last-smoke.log'), ($stdout.Result + $stderr.Result))
    if ($process.ExitCode -ne 0) { throw "CalculiX failed: exit $($process.ExitCode) (DLL/runtime or solver error)" }
    $dat = Join-Path $testDir 'smoke.dat'
    if (!(Test-Path -LiteralPath $dat)) { throw 'Benchmark did not produce smoke.dat' }
    $match = [regex]::Match((Get-Content -LiteralPath $dat -Raw), '(?m)^\s*2\s+([+\-0-9.EeDd]+)\s+([+\-0-9.EeDd]+)\s+([+\-0-9.EeDd]+)\s*$')
    if (!$match.Success) { throw 'Benchmark displacement missing' }
    $u = [double]::Parse(($match.Groups[1].Value -replace '[Dd]','E'), [Globalization.CultureInfo]::InvariantCulture)
    $expected = 6 * 1.3 * 0.4 / (1000 * 0.7)
    if ([double]::IsNaN($u) -or [double]::IsInfinity($u) -or [Math]::Abs($u - $expected) -gt $expected * 0.01) { throw "Benchmark outside 1% tolerance: $u expected $expected" }
    Log "Benchmark PASS executable=$exe displacement=$u expected=$expected"
  } finally {
    if ($process) { $process.Dispose() }
    if (!([IO.Path]::GetFullPath($testDir)).StartsWith($Root.TrimEnd('\') + '\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe cleanup target' }
    if (Test-Path -LiteralPath $testDir) { Remove-Item -LiteralPath $testDir -Recurse -Force }
  }
}
function Expand-VerifiedZip([string]$zip, [string]$target, [string]$executable) {
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $archive = [IO.Compression.ZipFile]::OpenRead($zip)
  try {
    if ($archive.Entries.Count -eq 0 -or $archive.Entries.Count -gt 20000) { throw 'Invalid ZIP entry count' }
    $seen = @{}; $total = 0L; $ccxCount = 0
    foreach ($entry in $archive.Entries) {
      $name = $entry.FullName.Replace('/','\'); $path = Child-Path $target $name
      if ($seen.ContainsKey($path)) { throw 'Duplicate ZIP path' }
      $seen[$path] = $true
      if ((($entry.ExternalAttributes -shr 16) -band 0xF000) -eq 0xA000) { throw 'ZIP symlink forbidden' }
      foreach ($part in ($name.TrimEnd('\') -split '\\')) {
        if ($part -match '[. ]$|^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\.|$)') { throw 'Unsafe Windows ZIP name' }
      }
      $total += $entry.Length
      if ($total -gt 2GB) { throw 'ZIP exceeds 2 GiB extracted' }
      if ([IO.Path]::GetFileName($path) -ieq 'ccx.exe') { $ccxCount++ }
    }
    if ($ccxCount -ne 1 -or !$seen.ContainsKey((Child-Path $target $executable))) { throw 'Expected one manifest ccx.exe' }
    # Inspeciona todas as entradas antes de extrair qualquer arquivo.
    foreach ($entry in $archive.Entries) {
      $path = Child-Path $target $entry.FullName.Replace('/','\')
      if ($entry.FullName.EndsWith('/') -or $entry.FullName.EndsWith('\')) { New-Item -ItemType Directory -Force -Path $path | Out-Null }
      else {
        New-Item -ItemType Directory -Force -Path (Split-Path $path) | Out-Null
        [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $path, $false)
      }
    }
  } finally { $archive.Dispose() }
}
if ($Action -eq 'Catalog') {
  $catalog = Get-Content -LiteralPath $CatalogPath -Raw | ConvertFrom-Json
  if ($catalog.schemaVersion -ne 1 -or $catalog.policy -ne 'deny-unverified') { throw 'Unsupported or untrusted catalog policy' }
  @($catalog.entries | Where-Object { $_.platform -eq 'windows' -and $_.arch -eq 'x64' -and $_.status -eq 'approved' -and $_.sha256 -match '^[a-fA-F0-9]{64}$' }) | ConvertTo-Json -Depth 8
  return
}
if ($Action -eq 'Status') {
  $exe = Read-Managed $active
  if ($exe) { Write-Output "Active: $exe" } else { Write-Output 'No managed CalculiX installed' }
  return
}
$lock = $null; $work = $null; $promoted = $null
try {
  $lock = [IO.File]::Open((Join-Path $Root 'manager.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
  if (@(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match '^ccx(?:[_.-].*)?$' }).Count) { throw 'CalculiX is running: wait for simulation to finish' }
  $old = Read-Managed $active
  if ($Action -eq 'Rollback') {
    $restore = Read-Managed $previous
    if (!$restore) { throw 'No previous version available' }
    Test-Solver $restore
    Activate-Version $restore $old
    Log "Rollback from=$old to=$restore"
    Write-Output "Rolled back to $restore"
    return
  }
  if ($ManifestPath) {
    $m = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
    Log 'Install requested with user-selected manifest'
  } else {
    $catalog = Get-Content -LiteralPath $CatalogPath -Raw | ConvertFrom-Json
    if ($catalog.schemaVersion -ne 1 -or $catalog.policy -ne 'deny-unverified') { throw 'Unsupported or untrusted catalog policy' }
    $entries = @($catalog.entries | Where-Object { $_.version -eq $Version -and $_.platform -eq 'windows' -and $_.arch -eq 'x64' -and $_.status -eq 'approved' })
    if ($entries.Count -ne 1) { throw 'Version not approved in catalog; no download performed' }
    $m = $entries[0]
    Log "Install requested from approved catalog version=$Version"
  }
  if (!$m.version -or $m.version -notmatch '^\d+\.\d+(\.\d+){0,2}$') { throw 'Invalid version' }
  if ($m.sha256 -notmatch '^[a-fA-F0-9]{64}$') { throw 'SHA256 required' }
  $uri = [Uri]$m.url
  if (!$uri.IsAbsoluteUri -or $uri.Scheme -ne 'https' -or $uri.UserInfo) { throw 'HTTPS URL required' }
  $rel = [string]$m.executable
  if ([IO.Path]::GetFileName($rel) -ine 'ccx.exe') { throw 'Manifest executable must be ccx.exe' }
  $destination = Child-Path $Root ('versions\' + $m.version)
  $exe = Child-Path $destination $rel
  if (Test-Path -LiteralPath $destination) {
    if ($old -and $old -ieq $exe) {
      Test-Solver $exe
      Write-Output "Already active and benchmark verified: $exe"
      return
    }
    throw 'Version already exists: use rollback; files preserved without changes'
  }
  $work = Join-Path $Root ('staging-' + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $work | Out-Null
  $zip = Join-Path $work 'package.zip'
  Log "Downloading version=$($m.version) source=$($uri.AbsoluteUri) old=$old"
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  Invoke-WebRequest -Uri $uri.AbsoluteUri -OutFile $zip -UseBasicParsing -TimeoutSec 180
  $stream = [IO.File]::OpenRead($zip)
  $hasher = [Security.Cryptography.SHA256]::Create()
  try { $hash = [BitConverter]::ToString($hasher.ComputeHash($stream)).Replace('-','') }
  finally { $stream.Dispose(); $hasher.Dispose() }
  if ($hash -ine $m.sha256) { throw 'SHA256 mismatch' }
  $extract = Join-Path $work 'extracted'
  Expand-VerifiedZip $zip $extract $rel
  foreach ($required in @($m.requiredFiles)) {
    if ($required -and !(Test-Path -LiteralPath (Child-Path $extract $required) -PathType Leaf)) { throw "Required dependency missing: $required" }
  }
  if (!$m.licenseFile -or !(Test-Path -LiteralPath (Child-Path $extract $m.licenseFile) -PathType Leaf)) { throw 'Package license file required' }
  New-Item -ItemType Directory -Force -Path (Split-Path $destination) | Out-Null
  Move-Item -LiteralPath $extract -Destination $destination
  $promoted = $destination
  Test-Solver $exe
  Activate-Version $exe $old
  $promoted = $null
  Log "Activated version=$($m.version) SHA256=$hash from=$old to=$exe"
  Write-Output "Installed and benchmark verified: $exe"
} catch { Log "FAILED: $($_.Exception.Message)"; throw }
finally {
  foreach ($candidate in @($work,$promoted)) {
    if (!$candidate) { continue }
    $checked = [IO.Path]::GetFullPath($candidate)
    if (!$checked.StartsWith($Root.TrimEnd('\') + '\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe cleanup target' }
    if (Test-Path -LiteralPath $checked) { Remove-Item -LiteralPath $checked -Recurse -Force }
  }
  if ($lock) { $lock.Dispose() }
}

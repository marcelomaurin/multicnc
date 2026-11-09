#requires -Version 5.1
<#
.SYNOPSIS
  Valida um ZIP local do CalculiX e executa a comparacao FEM sem instalar no sistema.
.EXAMPLE
  .\validate_calculix_zip.ps1 -ZipPath C:\Downloads\CalculiX-2.23.0-win-x64.zip -TestExe C:\MultiCNC\test_ccx.exe
#>
[CmdletBinding()]
param(
 [Parameter(Mandatory=$true)][string]$ZipPath,
 [Parameter(Mandatory=$true)][string]$TestExe,
 [string]$ExpectedSHA256,
 [string]$CCXRelativePath,
 [string]$ReportDir = (Join-Path $env:TEMP 'multiphysics-ccx-zip-validation')
)
$ErrorActionPreference='Stop'
$ZipPath=(Resolve-Path -LiteralPath $ZipPath).Path
$TestExe=(Resolve-Path -LiteralPath $TestExe).Path
New-Item -ItemType Directory -Force -Path $ReportDir | Out-Null
$log=Join-Path $ReportDir 'zip-validation.log'
function Log([string]$s) { Add-Content -LiteralPath $log -Value ("{0:o} {1}" -f (Get-Date),$s) }
$hash=(Get-FileHash -LiteralPath $ZipPath -Algorithm SHA256).Hash.ToLowerInvariant()
Log "ZIP=$ZipPath SHA256=$hash"
Write-Output "SHA256: $hash"
if ($ExpectedSHA256 -and $hash -ine $ExpectedSHA256) { Log 'FAIL hash mismatch'; throw 'SHA256 mismatch' }
if (!$ExpectedSHA256) { Log 'WARNING hash not pinned: local inspection only, not homologated' }
$work=Join-Path $ReportDir ('extracted-'+[guid]::NewGuid().ToString('N'))
try {
 New-Item -ItemType Directory -Force -Path $work | Out-Null
 # Inspect entries before extraction to block traversal and absolute paths.
 Add-Type -AssemblyName System.IO.Compression
 Add-Type -AssemblyName System.IO.Compression.FileSystem
 $archive=[IO.Compression.ZipFile]::OpenRead($ZipPath)
 try {
  $root=[IO.Path]::GetFullPath($work+[IO.Path]::DirectorySeparatorChar)
  foreach($entry in $archive.Entries) {
   $name=$entry.FullName.Replace('/',[IO.Path]::DirectorySeparatorChar)
   $target=[IO.Path]::GetFullPath((Join-Path $work $name))
   if (!$target.StartsWith($root,[StringComparison]::OrdinalIgnoreCase)) { throw "Unsafe ZIP entry: $($entry.FullName)" }
  }
 } finally { $archive.Dispose() }
 Expand-Archive -LiteralPath $ZipPath -DestinationPath $work
 if ($CCXRelativePath) {
  if ([IO.Path]::IsPathRooted($CCXRelativePath) -or $CCXRelativePath -match '(^|[\\/])\.\.([\\/]|$)') { throw 'Unsafe CCXRelativePath' }
  $candidate=Join-Path $work $CCXRelativePath
  if (!(Test-Path $candidate)) { throw "ccx.exe not found: $candidate" }
 } else {
  $candidates=@(Get-ChildItem -LiteralPath $work -Filter ccx.exe -File -Recurse)
  if ($candidates.Count -ne 1) { throw "Expected exactly one ccx.exe, found $($candidates.Count); specify -CCXRelativePath" }
  $candidate=$candidates[0].FullName
 }
 Log "CCX=$candidate"
 $runner=Join-Path $PSScriptRoot 'test_calculix_integration.ps1'
 if (!(Test-Path $runner)) { throw "Missing test runner: $runner" }
 & $runner -TestExe $TestExe -CalculixExe $candidate -ReportDir $ReportDir
 if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { throw "Test runner failed: $LASTEXITCODE" }
 Log 'PASS FEM validation; package not automatically approved without pinned hash'
 Write-Output "Validation logs: $ReportDir"
} catch {
 Log "FAIL: $($_.Exception.Message)"
 throw
} finally {
 if (Test-Path $work) { Remove-Item -LiteralPath $work -Recurse -Force }
}

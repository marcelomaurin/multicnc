#requires -Version 5.1
<#
  Executa teste de integracao real do CalculiX. Falha se solver ausente,
  ao contrario do test_ccx.lpr que permite IGNORADO.
  Uso: .\test_calculix_integration.ps1 -TestExe .\test_ccx.exe
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$TestExe,
  [string]$CalculixExe,
  [string]$ReportDir = (Join-Path $env:TEMP 'multiphysics-ccx-validation')
)
$ErrorActionPreference='Stop'
New-Item -ItemType Directory -Force -Path $ReportDir | Out-Null
$report = Join-Path $ReportDir 'ccx-validation.log'
function Write-Log([string]$line) {
  Add-Content -LiteralPath $report -Value ("{0:o} {1}" -f (Get-Date),$line)
}
if (!(Test-Path $TestExe)) { throw "test_ccx.exe not found: $TestExe" }
if (!$CalculixExe) {
  $active = Join-Path $env:LOCALAPPDATA 'MultiSuite\solvers\calculix\active.txt'
  if (Test-Path $active) { $CalculixExe=(Get-Content -LiteralPath $active -Raw).Trim() }
}
if (!$CalculixExe) { $cmd=Get-Command ccx.exe -ErrorAction SilentlyContinue; if ($cmd) { $CalculixExe=$cmd.Source } }
if (!$CalculixExe -or !(Test-Path $CalculixExe)) { Write-Log 'FAIL: CalculiX unavailable'; throw 'CalculiX required: missing solver' }
$env:CALCULIX_EXE = (Resolve-Path -LiteralPath $CalculixExe).Path
Write-Log "CalculiX: $env:CALCULIX_EXE"
$previous=$PWD
try {
  Set-Location -LiteralPath $ReportDir
  & (Resolve-Path -LiteralPath $TestExe).Path *>&1 | Tee-Object -FilePath (Join-Path $ReportDir 'test_ccx.output.txt')
  $code=$LASTEXITCODE
  Write-Log "test_ccx exit code: $code"
  if ($code -ne 0) { throw "FEM comparison failed: exit $code" }
  $output=Get-Content -LiteralPath (Join-Path $ReportDir 'test_ccx.output.txt') -Raw
  if ($output -match 'IGNORADO|SKIPPED') { throw 'Solver test was skipped' }
  Write-Log 'PASS: real CalculiX comparison completed'
} finally { Set-Location $previous }

# Compila e roda todos os testes de console do MultiPhysics (mesmo caminho
# de unidades da Central de Testes e do build do setup).
# Uso: powershell -ExecutionPolicy Bypass -File multiphysics\tests\run_all.ps1
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
if (-not $env:FPC) { $env:FPC = 'C:\lazarus\fpc\3.2.2\bin\x86_64-win64\fpc.exe' }
if (-not $env:MULTICNC_TEST_FLAGS) { $env:MULTICNC_TEST_FLAGS = '-Px86_64 -Twin64' }
$python = if ($env:PYTHON) { $env:PYTHON } else { 'python' }
& $python (Join-Path $root 'tools\verify_suite.py') console multiphysics
exit $LASTEXITCODE

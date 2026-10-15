param([string]$Lazarus = 'C:\lazarus')
$ErrorActionPreference = 'Stop'
Push-Location (Split-Path $PSScriptRoot -Parent)
$oldFpc = $env:FPC
$oldLazarus = $env:LAZARUS_DIR
$oldFlags = $env:MULTICNC_TEST_FLAGS
try {
  $env:LAZARUS_DIR = $Lazarus
  $env:FPC = Join-Path $Lazarus 'fpc/3.2.2/bin/i386-win32/fpc.exe'
  $env:MULTICNC_TEST_FLAGS = '-Px86_64 -Twin64'
  python tools/verify_print_tcp.py
  if ($LASTEXITCODE -ne 0) { throw 'TCP printing integration failed' }
} finally {
  $env:FPC = $oldFpc
  $env:LAZARUS_DIR = $oldLazarus
  $env:MULTICNC_TEST_FLAGS = $oldFlags
  Pop-Location
}

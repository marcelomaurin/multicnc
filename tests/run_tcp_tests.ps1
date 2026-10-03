param([string]$Lazarus = 'C:\lazarus')
$ErrorActionPreference = 'Stop'
Push-Location (Split-Path $PSScriptRoot -Parent)
try {
  & "$Lazarus\lazbuild.exe" src/simucnc/simucnc.lpi
  if ($LASTEXITCODE -ne 0) { throw 'SimuCNC build failed' }
  New-Item -ItemType Directory -Force tests/lib | Out-Null
  & "$Lazarus\fpc\3.2.2\bin\i386-win32\fpc.exe" '-Fusrc/app' '-Fusrc/core' '-Fusrc/transports' '-Fusrc/protocols' '-Fu..\CHATGPT\pacote\AI Input\AISerial' '-Fu..\CHATGPT\pacote\AI' "-Fu$Lazarus\lcl\units\i386-win32" "-Fu$Lazarus\components\lazutils\lib\i386-win32" '-FUtests/lib' '-FEtests/lib' tests/test_multicnc_tcp.lpr
  if ($LASTEXITCODE -ne 0) { throw 'Client test build failed' }
  python tests/test_simucnc_tcp.py
  if ($LASTEXITCODE -ne 0) { throw 'TCP integration failed' }
} finally { Pop-Location }

param([string]$LazarusDir = 'C:\lazarus', [switch]$Test)
$ErrorActionPreference = 'Stop'
$compiler = Join-Path $LazarusDir 'fpc\3.2.2\bin\x86_64-win64\fpc.exe'
$builder = Join-Path $LazarusDir 'lazbuild.exe'
Push-Location $PSScriptRoot
try {
    & $builder "--lazarusdir=$LazarusDir" "--pcp=$PSScriptRoot\.lazarus-build" "--compiler=$compiler" --ws=win32 multicnc.lpi
    if ($LASTEXITCODE -ne 0) { throw 'Compilação do aplicativo falhou.' }
    if ($Test) {
        New-Item -ItemType Directory -Force -Path 'lib\tests','bin' | Out-Null
        & $compiler -MObjFPC -Sh -gl '-Fu./src' '-FU./lib/tests' '-FE./bin' tests/test_core.lpr
        if ($LASTEXITCODE -ne 0) { throw 'Compilação dos testes falhou.' }
        & '.\bin\test_core.exe'
        if ($LASTEXITCODE -ne 0) { throw 'Testes falharam.' }
    }
} finally { Pop-Location }

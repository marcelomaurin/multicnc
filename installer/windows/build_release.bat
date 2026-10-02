@echo off
setlocal
cd /d "%~dp0\..\.."
set ROOT=%CD%
set DIST=%ROOT%\dist
set APP=%DIST%\app
if not defined VERSION set VERSION=0.1.1-dev
if exist "%APP%" rmdir /s /q "%APP%"
mkdir "%APP%"

where lazbuild >nul 2>nul || (echo ERRO: lazbuild nao encontrado no PATH.& exit /b 1)

call :build multisuite\src\app\multisuite.lpi multisuite\src\app\multisuite.exe multisuite.exe || exit /b 1
call :build multicad\src\app\multicad.lpi multicad\src\app\multicad.exe multicad.exe || exit /b 1
call :build multipcb\src\app\multipcb.lpi multipcb\src\app\multipcb.exe multipcb.exe || exit /b 1
call :build multiassembly\src\app\multiassembly.lpi multiassembly\src\app\multiassembly.exe multiassembly.exe || exit /b 1
call :build multiphysics\src\app\multiphysics.lpi multiphysics\src\app\multiphysics.exe multiphysics.exe || exit /b 1
call :build multicam\src\app\multicam.lpi multicam\src\app\multicam.exe multicam.exe || exit /b 1
call :build multislicer\src\app\multislicer.lpi multislicer\src\app\multislicer.exe multislicer.exe || exit /b 1
call :build laserpcb\src\app\laserpcb.lpi laserpcb\src\app\laserpcb.exe laserpcb.exe || exit /b 1
call :build laserpcb\src\app\laserart.lpi laserpcb\src\app\laserart.exe laserart.exe || exit /b 1
call :build src\app\multicnc.lpi src\app\multicnc.exe multicnc.exe || exit /b 1
call :build multisuite\src\testing\multisuite_test_center.lpi multisuite\src\testing\multisuite_test_center.exe multisuite_test_center.exe || exit /b 1

rem Testes de console sao executados e incluidos na Central de Testes instalada.
python tools\verify_suite.py console --stage "%APP%" || exit /b 1
xcopy /E /I /Y docs "%APP%\docs" >nul || exit /b 1

rem Remove informacao de debug dos executaveis distribuidos (~26 MB -> ~4 MB cada).
rem strip.exe acompanha o Lazarus (fpc\<versao>\bin\x86_64-win64); se nao estiver no PATH, segue sem strip.
where strip >nul 2>nul && (for %%F in ("%APP%\*.exe") do strip --strip-debug "%%F") || echo AVISO: strip nao encontrado; executaveis mantem informacao de debug.

python tools\release_manifest.py --app-dir "%APP%" --version "%VERSION%" --os windows --arch amd64 --require-clean --version-include "%DIST%\version.iss" || exit /b 1

where iscc >nul 2>nul || (echo ERRO: Inno Setup ISCC nao encontrado no PATH.& exit /b 2)
iscc installer\windows\multisuite.iss || exit /b 3
powershell -NoProfile -Command "$p=Get-Item 'dist\MultiSuite-Setup-%VERSION%-win64.exe'; ((Get-FileHash $p.FullName -Algorithm SHA256).Hash.ToLower()+'  '+$p.Name) | Set-Content -Encoding ascii 'dist\SHA256SUMS'" || exit /b 1
echo.
echo Instalador gerado em dist\
exit /b 0

:build
echo === Compilando %~1 ===
if exist "%~2" del /q "%~2"
lazbuild --build-mode=Default "%~1" || exit /b 1
if not exist "%~2" (echo ERRO: executavel nao encontrado: %~2& exit /b 1)
copy /y "%~2" "%APP%\%~3" >nul
exit /b 0

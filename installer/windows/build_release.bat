@echo off
setlocal
cd /d "%~dp0\..\.."
set ROOT=%CD%
set DIST=%ROOT%\dist
set APP=%DIST%\app
set BIN=%ROOT%\bin

set VERSION=%~1
if "%VERSION%"=="" set VERSION=0.02

set SETUP_SEQ=%~2
if "%SETUP_SEQ%"=="" set SETUP_SEQ=002

set OUTPUT_NAME=setup_multcnc_%SETUP_SEQ%

if exist "%DIST%" rmdir /s /q "%DIST%"
mkdir "%APP%"
if not exist "%BIN%" mkdir "%BIN%"

where lazbuild >nul 2>nul || (echo ERRO: lazbuild nao encontrado no PATH.& exit /b 1)

call :build multisuite\src\app\multisuite.lpi multisuite\src\app\multisuite.exe multisuite.exe || exit /b 1
call :build multicad\src\app\multicad.lpi multicad\src\app\multicad.exe multicad.exe || exit /b 1
call :build multipcb\src\app\multipcb.lpi multipcb\src\app\multipcb.exe multipcb.exe || exit /b 1
call :build multiassembly\src\app\multiassembly.lpi multiassembly\src\app\multiassembly.exe multiassembly.exe || exit /b 1
call :build multiphysics\src\app\multiphysics.lpi multiphysics\src\app\multiphysics.exe multiphysics.exe || exit /b 1
call :build multicam\src\app\multicam.lpi multicam\src\app\multicam.exe multicam.exe || exit /b 1
call :build multislicer\src\app\multislicer.lpi multislicer\src\app\multislicer.exe multislicer.exe || exit /b 1
call :build makepcb\src\app\makepcb.lpi makepcb\src\app\makepcb.exe makepcb.exe || exit /b 1
call :build laserpcb\src\app\laserpcb.lpi laserpcb\src\app\laserpcb.exe laserpcb.exe || exit /b 1
call :build laserart\src\app\laserart.lpi laserart\src\app\laserart.exe laserart.exe || exit /b 1
call :build src\app\multicnc.lpi src\app\multicnc.exe multicnc.exe || exit /b 1
call :build multisuite\src\tray\multisuite_tray.lpi multisuite\src\tray\multisuite_tray.exe multisuite_tray.exe || exit /b 1
call :build src\simucnc\simucnc.lpi src\simucnc\SimuCNC.exe SimuCNC.exe || exit /b 1
call :build multisuite\src\testing\multisuite_test_center.lpi multisuite\src\testing\multisuite_test_center.exe multisuite_test_center.exe || exit /b 1

where strip >nul 2>nul && (for %%F in ("%APP%\*.exe") do strip --strip-debug "%%F") || echo AVISO: strip nao encontrado; executaveis mantem informacao de debug.

where iscc >nul 2>nul || (echo ERRO: Inno Setup ISCC nao encontrado no PATH.& exit /b 2)
iscc "-dMyAppVersion=%VERSION%" "-dSetupSeq=%SETUP_SEQ%" "-dOutputExeName=%OUTPUT_NAME%" installer\windows\multisuite.iss || exit /b 3

if exist "%DIST%\%OUTPUT_NAME%.exe" (
  copy /y "%DIST%\%OUTPUT_NAME%.exe" "%BIN%\%OUTPUT_NAME%.exe" >nul
  echo Instalador copiado para: bin\%OUTPUT_NAME%.exe
)

echo.
echo Instalador gerado com sucesso em dist\ e bin\
exit /b 0

:build
echo === Compilando %~1 ===
if exist "%~2" del /q "%~2"
lazbuild --build-mode=Default "%~1" || exit /b 1
if not exist "%~2" (echo ERRO: executavel nao encontrado: %~2& exit /b 1)
copy /y "%~2" "%APP%\%~3" >nul
exit /b 0

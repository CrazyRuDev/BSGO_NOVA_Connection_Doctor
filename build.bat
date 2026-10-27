@echo off
setlocal
rem Builds build\BSGO_Tester.exe from src\BSGO_Tester.ahk with AutoHotkey v2 Ahk2Exe.

set "AHK2EXE=%ProgramFiles%\AutoHotkey\Compiler\Ahk2Exe.exe"
set "BASE=%ProgramFiles%\AutoHotkey\v2\AutoHotkey64.exe"

if not exist "%AHK2EXE%" (
    echo Ahk2Exe not found: install AutoHotkey v2 together with the compiler.
    goto :fail
)
if not exist "%BASE%" (
    echo AutoHotkey v2 64-bit not found: %BASE%
    goto :fail
)
if not exist "%~dp0build" mkdir "%~dp0build"

"%AHK2EXE%" /in "%~dp0src\BSGO_Tester.ahk" /out "%~dp0build\BSGO_Tester.exe" /base "%BASE%"
if errorlevel 1 goto :fail

echo.
echo Built: build\BSGO_Tester.exe
if not defined NOPAUSE pause
exit /b 0

:fail
echo Build failed.
if not defined NOPAUSE pause
exit /b 1

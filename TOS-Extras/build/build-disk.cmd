@echo off
REM Build the Optional Utilities disk from TOS-Extras (Windows wrapper).
REM
REM Usage:  TOS-Extras\build\build-disk.cmd [--install <dir>]
REM
REM Output: TOS-Extras\dist\optional-utilities
REM --install also copies the disk contents into <dir> — point it at an
REM OpenComputers floppy folder (saves\<world>\opencomputers\<address>\)
REM to "burn" the disk in one step.

setlocal enableextensions
set "SCRIPT_DIR=%~dp0"
for %%I in ("%SCRIPT_DIR%..") do set "EXTRAS_DIR=%%~fI"

where lua >nul 2>nul
if errorlevel 1 (
    echo error: lua not found in PATH 1>&2
    echo        install with:  winget install DEVCOM.Lua 1>&2
    exit /b 1
)

lua "%SCRIPT_DIR%build-disk.lua" "%EXTRAS_DIR%" "%EXTRAS_DIR%\dist\optional-utilities" %*
exit /b %ERRORLEVEL%

@echo off
REM Build TOS-Release from TOS-Dev (Windows wrapper).
REM
REM Usage:  TOS-Dev\build\build-release.cmd
REM
REM Excludes: /build/, /usr/lib/tests/, /run_tests.sh, /.claude/   (dev-only)
REM This is a DENYLIST: anything in TOS-Dev's root not named below ships.
REM Keep it identical to build-release.sh; test_release_excludes.lua checks
REM every top-level entry against both.
REM Post-pass: strip.lua auto-prunes system_manifest.lua against the dist tree.
REM
REM --minify-vars (whitespace minify + local-variable renaming, via the
REM vendored/patched stravant/LuaMinify in build\vendor\luaminify\) is the
REM default: 1907.2 KB -> 1313.2 KB on the 2 MB drive budget (2026-10-17,
REM includes build\vendor\luaminify's DedupStrings pass).
REM Drop to --minify if that pass is ever suspected of a regression --
REM see build\vendor\luaminify\README.md first.

setlocal enableextensions
set "SCRIPT_DIR=%~dp0"
for %%I in ("%SCRIPT_DIR%..") do set "DEV_DIR=%%~fI"
for %%I in ("%DEV_DIR%\..") do set "ROOT_DIR=%%~fI"
set "RELEASE_DIR=%ROOT_DIR%\TOS-Release"

where lua >nul 2>nul
if errorlevel 1 (
    echo error: lua not found in PATH 1>&2
    echo        install with:  winget install DEVCOM.Lua 1>&2
    exit /b 1
)

if exist "%RELEASE_DIR%" rmdir /s /q "%RELEASE_DIR%"
mkdir "%RELEASE_DIR%"

pushd "%ROOT_DIR%"
lua "%DEV_DIR%\build\strip.lua" "%DEV_DIR%" "%RELEASE_DIR%" --minify-vars ^
    --exclude /build/ ^
    --exclude /usr/lib/tests/ ^
    --exclude /TOS-Extras/ ^
    --exclude /run_tests.sh ^
    --exclude /run_tests.py ^
    --exclude /todo_index.py ^
    --exclude /tos.py ^
    --exclude /.claude/ ^
    --exclude /.pytest_cache/ ^
    --exclude /.git/ ^
    --exclude /.github/ ^
    --exclude /.gitignore ^
    --exclude /docs/ ^
    --exclude /README.md ^
    --exclude /CHANGELOG.md ^
    --exclude /CONTRIBUTING.md ^
    --exclude /ROADMAP.md ^
    --exclude /SECURITY.md ^
    --exclude /Codenames.txt ^
    --exclude /TODO.txt ^
    --exclude /MANUAL.md ^
    --exclude /EMULATOR_CHECKLIST.md
set "RC=%ERRORLEVEL%"
popd

if "%RC%" == "0" echo. & echo Release built at: %RELEASE_DIR%
exit /b %RC%

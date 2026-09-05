# Build the Optional Utilities disk from TOS-Extras (PowerShell wrapper).
#
# Usage:  .\TOS-Extras\build\build-disk.ps1 [--install <dir>] [--limit <size>]
#
# Why this exists alongside build-disk.cmd:
#   Invoking the .cmd wrapper FROM POWERSHELL prints a few stray
#   "'M' is not recognized" lines to stderr before the (correct) build
#   output. The noise is cosmetic — the disks assemble identically — but
#   it trains you to ignore build errors, which is a bad habit to teach a
#   toolchain. It was tracked to the PowerShell -> cmd.exe -> lua
#   invocation specifically: the Lua builder is silent when run directly
#   (verified with an os.execute/io.popen tracer: it makes NO subprocess
#   calls at all when LuaFileSystem is installed), the .cmd wrapper is
#   silent with the lua line removed, and every wrapper line is silent in
#   isolation. Only the exact combination misbehaves.
#
#   So on PowerShell, skip the middleman: this calls lua directly, which
#   is clean. build-disk.cmd remains correct from cmd.exe, and
#   build-disk.sh from POSIX/Git Bash.

$ErrorActionPreference = 'Stop'

$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$ExtrasDir  = (Resolve-Path (Join-Path $ScriptDir '..')).Path
$BuilderLua = Join-Path $ScriptDir 'build-disk.lua'
$OutDir     = Join-Path $ExtrasDir 'dist\optional-utilities'

if (-not (Get-Command lua -ErrorAction SilentlyContinue)) {
    Write-Error "lua not found in PATH. Install with:  winget install DEVCOM.Lua"
    exit 1
}
if (-not (Test-Path $BuilderLua)) {
    Write-Error "build-disk.lua not found next to this script ($BuilderLua)"
    exit 1
}

# LuaFileSystem makes the builder entirely subprocess-free (mkdir, rmdir
# and directory listing all go through lfs instead of shelling out).
# Without it the builder still works via shell fallbacks, but those
# inherit the quoting rules of whichever shell launched them — which is
# where build gremlins come from. Worth saying out loud once.
$hasLfs = (& lua -e 'print(pcall(require, "lfs") and "yes" or "no")' 2>$null)
if ($hasLfs -ne 'yes') {
    Write-Host "note: LuaFileSystem not installed — the builder will shell out for" -ForegroundColor DarkYellow
    Write-Host "      directory operations. Install it for a subprocess-free build:" -ForegroundColor DarkYellow
    Write-Host "        luarocks install luafilesystem" -ForegroundColor DarkYellow
}

& lua $BuilderLua $ExtrasDir $OutDir @args
exit $LASTEXITCODE

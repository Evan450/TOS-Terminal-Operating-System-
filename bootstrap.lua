local component = require("component")
local computer = require("computer")
local term = require("term")

local fs = nil
pcall(function() fs = require("filesystem") end)

local gpu = component.gpu

local function color(fg)
  if gpu and gpu.setForeground then
    pcall(gpu.setForeground, fg)
  end
end

local function ok(msg)
  color(0x00FF00); print("  + " .. msg); color(0xFFFFFF)
end

local function warn(msg)
  color(0xFFFF00); print("  ! " .. msg); color(0xFFFFFF)
end

local function fail(msg)
  color(0xFF0000); print("  X " .. msg); color(0xFFFFFF)
end

local function ask(question, options, default)
  color(0xFFFF00)
  io.write(question)
  if options then
    color(0xAAAAAA)
    io.write(" [" .. table.concat(options, "/") .. "]")
  end
  if default then
    color(0x888888)
    io.write(" (default: " .. default .. ")")
  end
  color(0xFFFFFF)
  io.write(": ")
  local answer
  if term and term.read then
    local okT, result = pcall(term.read)
    if okT then
      answer = result
      if answer then answer = answer:gsub("\n$", "") end
    end
  else
    answer = io.read()
  end
  if not answer or answer == "" then return default end
  return answer
end

local function confirm(question)
  local answer = ask(question, {"y", "n"}, "y")
  return answer and (answer:lower() == "y" or answer:lower() == "yes")
end

local function pause(seconds)

  if os.sleep then pcall(os.sleep, seconds) end
end

local BOOTSTRAP_VERSION = "1.0.0"

local LOGO_MARK = {
  "████████  ████████  ████████",
  "   ██     ██    ██  ██      ",
  "   ██     ██    ██  ████████",
  "   ██     ██    ██        ██",
  "   ██     ████████  ████████",
}

local function header()
  color(0x00AAFF)
  for _, ln in ipairs(LOGO_MARK) do print("   " .. ln) end
  color(0xFFFFFF); print()
  color(0x00FF66); print("   Strata Systems LLC"); color(0xFFFFFF)
  color(0xAAAAAA)
  print("   Terminal Operating System — Network Bootstrap v" .. BOOTSTRAP_VERSION)
  color(0xFFFFFF)
  print()
end

local DEFAULT_OWNER = "Evan450"
local DEFAULT_REPO  = "TOS-Terminal-Operating-System-"

local BRANCH_CANDIDATES = { "main", "master" }

local SUBDIR_CANDIDATES = { "", "TOS-Release" }

--! A CLI-supplied owner/repo/branch/subdir becomes part of an HTTPS URL
--! below. Restricting the charset here isn't a security boundary against
--! a hostile operator (they could just as easily hand-edit the URL), but
--! it does stop a typo or stray whitespace from building a malformed or
--! surprising request — the same spirit as kernel.internet's URL vetting,
--! kept local because this script runs before that module is reachable.
local function safeToken(s)
  return type(s) == "string" and s ~= "" and not s:find("[%c]")
    and s:match("^[%w%.%-_/]+$") ~= nil
end

local function internetCard()
  local addr = component.list("internet")()
  if not addr then return nil end
  local okP, p = pcall(component.proxy, addr)
  if not okP then return nil end
  return p
end

local MAX_FILE_BYTES    = 96 * 1024
local REQUEST_TIMEOUT   = 20
local DOWNLOAD_RETRIES  = 3
local PROBE_RETRIES     = 2

local function httpGet(card, url, retries)
  retries = retries or DOWNLOAD_RETRIES
  for attempt = 1, retries do
    local okReq, handle, reason = pcall(card.request, url, nil,
      { ["user-agent"] = "TOS-Bootstrap/" .. BOOTSTRAP_VERSION })
    if okReq and handle then
      local parts, total, status = {}, 0, nil
      local failed, failReason = false, nil
      local deadline = computer.uptime() + REQUEST_TIMEOUT
      while true do
        local okRead, chunk, readErr = pcall(handle.read)
        if not okRead then failed = true; failReason = tostring(chunk); break end
        if handle.response and not status then
          local okR, code = pcall(handle.response)
          if okR and code then status = code end
        end
        if chunk == nil then
          if readErr then failed = true; failReason = tostring(readErr) end
          break
        end
        if #chunk > 0 then
          total = total + #chunk
          if total > MAX_FILE_BYTES then
            failed = true
            failReason = "response exceeds " .. MAX_FILE_BYTES .. " bytes"
            break
          end
          parts[#parts + 1] = chunk
          deadline = computer.uptime() + REQUEST_TIMEOUT
        else
          pause(0)
        end
        if computer.uptime() > deadline then
          failed = true; failReason = "timed out after " .. REQUEST_TIMEOUT .. "s"
          break
        end
      end
      pcall(function() handle.close() end)
      if not failed then
        if status and status ~= 200 then
          return nil, "HTTP " .. tostring(status), status
        end
        return table.concat(parts), nil, status
      end
      if attempt < retries then pause(1) end
    else
      if attempt < retries then pause(1) end
    end
  end
  return nil, "request failed after " .. retries .. " attempt(s)"
end

local function rawUrl(owner, repo, branch, subdir, path)
  local prefix = (subdir ~= "" and ("/" .. subdir) or "")
  return string.format("https://raw.githubusercontent.com/%s/%s/%s%s%s",
    owner, repo, branch, prefix, path)
end

local function parseManifest(source)
  if #source > 256 * 1024 then
    return nil, "manifest exceeds 256 KB sanity cap"
  end
  local fn, err = load(source, "=manifest", "t", {})
  if not fn then return nil, "manifest parse error: " .. tostring(err) end
  local ok2, result = pcall(fn)
  if not ok2 then return nil, "manifest run error: " .. tostring(result) end
  if type(result) ~= "table" then return nil, "manifest did not return a table" end
  return result
end

term.clear()
header()

if not fs then
  fail("OpenOS filesystem library unavailable — cannot stage a download.")
  warn("Run this from OpenOS, not a bare Lua interpreter.")
  return
end

local card = internetCard()
if not card then
  fail("No Internet Card found on this computer.")
  warn("Craft one (Tier 1 is enough) and place it in this computer or")
  warn("server, or install from a physical disk with install.lua instead.")
  return
end
ok("Internet Card found")
print()

local cliArgs = {...}
local owner, repoName = DEFAULT_OWNER, DEFAULT_REPO
if cliArgs[1] then
  local o, r = cliArgs[1]:match("^([^/]+)/(.+)$")
  if o and r and safeToken(o) and safeToken(r) then
    owner, repoName = o, r
  else
    warn("Ignoring malformed owner/repo argument: " .. tostring(cliArgs[1]))
  end
end
local branches = BRANCH_CANDIDATES
if cliArgs[2] then
  if safeToken(cliArgs[2]) then branches = { cliArgs[2] }
  else warn("Ignoring malformed branch argument: " .. tostring(cliArgs[2])) end
end
local subdirs = SUBDIR_CANDIDATES
if cliArgs[3] ~= nil then
  if cliArgs[3] == "" or safeToken(cliArgs[3]) then subdirs = { cliArgs[3] }
  else warn("Ignoring malformed subdir argument: " .. tostring(cliArgs[3])) end
end

ok("Repository: " .. owner .. "/" .. repoName)
print()

if not confirm("Download TOS from the internet and install it here?") then
  print("Cancelled.")
  return
end
print()

color(0x00AAFF); print("--- Locating release files ---"); color(0xFFFFFF)
local baseBranch, baseSubdir, manifestSrc
for _, branch in ipairs(branches) do
  for _, subdir in ipairs(subdirs) do
    local label = branch .. (subdir ~= "" and ("/" .. subdir) or "")
    io.write("  probing " .. label .. " ... ")
    local url = rawUrl(owner, repoName, branch, subdir, "/tos/system_manifest.lua")
    local body, err = httpGet(card, url, PROBE_RETRIES)
    if body and #body > 0 then
      color(0x00FF00); print("found"); color(0xFFFFFF)
      baseBranch, baseSubdir, manifestSrc = branch, subdir, body
      break
    else
      color(0xAAAAAA); print("not there (" .. tostring(err) .. ")"); color(0xFFFFFF)
    end
  end
  if manifestSrc then break end
end
print()

if not manifestSrc then
  --! A repo can be reachable, current, and still unusable: if its files
  --! were uploaded WITHOUT their directory structure (everything dumped
  --! at the root), the manifest is there but every path it declares —
  --! /tos/kernel/init.lua and the rest — resolves to nothing. Worse, a
  --! flat layout is lossy in a way no download logic can undo: TOS ships
  --! six different init.lua files (kernel, net, shell, panels, compat,
  --! and the root boot loader) plus two event.lua and two internet.lua,
  --! and a flat repo can hold exactly one of each. Detect that shape and
  --! say so, rather than leaving an operator staring at four 404s.
  local flat = httpGet(card, rawUrl(owner, repoName, branches[1], "",
    "/system_manifest.lua"), PROBE_RETRIES)
  if flat and #flat > 0 then
    fail("This repo has a FLAT layout — no directory structure.")
    warn("system_manifest.lua is at the root, but the files it declares")
    warn("(/tos/kernel/init.lua and the rest) have no directories to live")
    warn("in. That cannot be installed from, and it cannot be repaired by")
    warn("downloading harder: TOS ships six separate init.lua files, and a")
    warn("flat repo can only hold one of them.")
    warn("Fix: push the release tree WITH its directories (tos/, etc/,")
    warn("usr/) to the repo, then re-run this script.")
    return
  end
  fail("Could not find a TOS release under " .. owner .. "/" .. repoName ..
    " on any of: " .. table.concat(branches, ", "))
  warn("If this is a fork or the layout changed, point at it directly:")
  warn("  bootstrap.lua " .. owner .. "/" .. repoName .. " <branch> <subdir>")
  return
end

local manifest, mErr = parseManifest(manifestSrc)
if not manifest then
  fail("Cannot parse the downloaded manifest: " .. tostring(mErr))
  return
end
ok("Using " .. owner .. "/" .. repoName .. "@" .. baseBranch ..
  (baseSubdir ~= "" and ("/" .. baseSubdir) or "") ..
  " (" .. #manifest .. " files declared)")
print()

local stagingDir = (fs.isDirectory("/tmp") and "/tmp/tos-netinstall")
  or "/tos-netinstall-tmp"
if fs.exists(stagingDir) then
  warn("Removing a stale staging directory from a previous run: " .. stagingDir)
  pcall(fs.remove, stagingDir)
end
if not fs.makeDirectory(stagingDir) then
  fail("Cannot create staging directory: " .. stagingDir)
  return
end

local fileList, seen = {}, {}
for _, entry in ipairs(manifest) do
  if type(entry) == "table" and type(entry.path) == "string" and not seen[entry.path] then
    seen[entry.path] = true
    fileList[#fileList + 1] = entry.path
  end
end
if not seen["/install.lua"] then fileList[#fileList + 1] = "/install.lua" end
if not seen["/bios.lua"] then fileList[#fileList + 1] = "/bios.lua" end

color(0x00AAFF)
print("--- Downloading " .. #fileList .. " files ---")
color(0xFFFFFF)
local copied, failed = 0, 0
local failedPaths = {}
for i, path in ipairs(fileList) do
  local dir = path:match("^(.+)/[^/]+$")
  if dir then
    local acc = ""
    for seg in dir:gmatch("[^/]+") do
      acc = acc .. "/" .. seg
      if not fs.isDirectory(stagingDir .. acc) then fs.makeDirectory(stagingDir .. acc) end
    end
  end
  local url = rawUrl(owner, repoName, baseBranch, baseSubdir, path)
  local body, err = httpGet(card, url)
  if body then
    local f = io.open(stagingDir .. path, "w")
    if f then
      f:write(body); f:close()
      copied = copied + 1
    else
      failed = failed + 1
      failedPaths[#failedPaths + 1] = path .. ": cannot open staging file for write"
    end
  else

    if path == "/bios.lua" then

    else
      failed = failed + 1
      failedPaths[#failedPaths + 1] = path .. ": " .. tostring(err)
    end
  end
  if i % 10 == 0 or i == #fileList then
    io.write(string.format("\r  %d/%d files (%d failed)   ", i, #fileList, failed))
  end
end
print()
print()

if failed == 0 then
  ok("Downloaded " .. copied .. " files")
else
  fail(failed .. " file(s) failed to download:")
  for i = 1, math.min(5, #failedPaths) do warn("  " .. failedPaths[i]) end
  if #failedPaths > 5 then warn("  (+" .. (#failedPaths - 5) .. " more)") end
end
print()

local installPath = stagingDir .. "/install.lua"
local installStaged = fs.exists(installPath) and (fs.size(installPath) or 0) > 0
if not installStaged then
  fail("install.lua did not download successfully — nothing to hand off to.")
  warn("Retry, or point at the release directly if the layout is nonstandard:")
  warn("  bootstrap.lua " .. owner .. "/" .. repoName .. " " .. baseBranch ..
    (baseSubdir ~= "" and (" " .. baseSubdir) or " \"\""))
  return
end

color(0x00AAFF); print("--- Handing off to install.lua ---"); color(0xFFFFFF)
ok("Staged at " .. stagingDir)
print()

local chunk, lerr = loadfile(installPath)
if not chunk then
  fail("Downloaded install.lua does not parse: " .. tostring(lerr))
  warn("The file may have been corrupted in transit — try again.")
  return
end

local hok, herr = pcall(chunk, stagingDir)
if not hok then
  fail("install.lua exited with an error: " .. tostring(herr))
  warn("You can retry it directly:")
  warn("  " .. installPath .. " " .. stagingDir)
end

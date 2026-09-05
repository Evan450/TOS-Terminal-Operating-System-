-- ╔══════════════════════════════════════════════════════════╗
-- ║  TOS Shell - Commands subfile                            ║
-- ║  Auto-extracted from commands.lua during the v1.3 split  ║
-- ║  to bring per-file size under ~500 lines and enable      ║
-- ║  lazy-loading via the dispatcher.                        ║
-- ║                                                          ║
-- ║  Each subfile exports a single registration function     ║
-- ║  that adds its commands to the shared C table. The       ║
-- ║  dispatcher in commands.lua loads each subfile only on   ║
-- ║  first access to one of its commands.                    ║
-- ╚══════════════════════════════════════════════════════════╝

local computer   = require("computer")
local component  = require("component")
local helpers    = require("shell.panels.helpers")

return function(C, S, deps)
  -- Stable references aliased as locals (avoids per-call S/deps lookup).
  local K, E, P, F, D, U = S.K, S.E, S.P, S.F, S.D, S.U
  local SC, NM, st        = S.SC, S.NM, S.st
  local T                 = S.T
  local tier              = S.tier
  local W, H              = S.W, S.H
  local rp                = deps.rp
  local openViewTab       = deps.openViewTab
  local openEditTab       = deps.openEditTab
  local refreshBrowser    = deps.refreshBrowser
  local canRead           = deps.canRead
  local canWrite          = deps.canWrite
  local canAccess         = deps.canAccess
  local rootOnly          = deps.rootOnly
  local adminOnly         = deps.adminOnly
  local makeProgramEnv    = deps.makeProgramEnv
  local fmtSz             = helpers.fmtSz
  local expandBuf         = function(buf) return helpers.expandBuf(S, buf) end
  local promptInput       = deps.promptInput

  C.kill = function(args, o)
    -- #SEC C7 — process control is an admin capability (REGISTRY tier=2,
    -- matching the sibling bg/run/fg commands). The kernel's proc.kill
    -- already enforces per-process ownership, but the in-body tier gate is
    -- the documented belt-and-braces line: the executor performs NO
    -- dispatch-level tier check, so a missing guard here let any logged-in
    -- user (including GUEST) invoke kill directly.
    if not adminOnly(o) then return end
    if not args[1] then o("Usage: kill <pid>", T.dim); return end
    local pid = tonumber(args[1])
    if pid then
      local ok2, err = P.kill(pid)
      if ok2 then o("Killed PID " .. pid, T.highlight) else o(tostring(err), T.error) end
    else o("Invalid PID", T.error) end
  end

  C.fg = function(args, o)
    -- #SEC C7/H13 — admin-gated (REGISTRY tier=2). Without this guard a
    -- GUEST could point their own seat's foreground at another user's
    -- process; proc.tick then delivers the guest's keystrokes to that
    -- process — input injection into a higher-privileged session. The
    -- kernel proc.setForeground now also enforces target ownership, but
    -- this is the documented in-body tier gate (the executor does not gate).
    if not adminOnly(o) then return end
    if not args[1] then o("Usage: fg <pid>", T.dim); return end
    local pid = tonumber(args[1])
    if not pid or not P.get(pid) then o("No such process", T.error); return end
    local ok, err = P.setForeground(pid, S.displayIdx)
    if not ok then o(tostring(err or "Cannot foreground that process"), T.error); return end
    o("Foreground: PID " .. pid, T.highlight)
  end

  C.verify = function(args, o)
    if not adminOnly(o) then return end

    -- `verify anchor` / `verify anchor --clear` — the operator-facing half
    -- of #SEC C1. The manifest hash is anchored in the EEPROM data field so
    -- a later boot can prove the manifest wasn't swapped. `doctor` used to
    -- tell operators to "run kernel.anchorManifestHash()", which is a
    -- kernel function with no shell surface — unrunnable anywhere they
    -- could reach. This is that surface.
    local sub = args and args[1] and tostring(args[1]):lower()
    if sub == "anchor" then
      local clear = false
      for i = 2, #args do
        local a = tostring(args[i]):lower()
        if a == "--clear" or a == "clear" then clear = true end
      end
      if clear then
        if not K.clearManifestAnchor then
          o("This TOS build cannot clear the anchor.", T.error); return
        end
        local ok2, err2 = K.clearManifestAnchor()
        if ok2 then o("Manifest anchor cleared. `doctor` will report it un-anchored.", T.highlight)
        else o("Could not clear the anchor: " .. tostring(err2), T.error) end
        return
      end
      if not K.anchorManifestHash then
        o("This TOS build has no manifest anchoring.", T.error); return
      end
      -- Anchor AFTER confirming the files actually match the manifest —
      -- anchoring a system you haven't verified just certifies whatever
      -- happens to be on disk, including damage.
      o("Anchoring records THIS system's manifest hash in the EEPROM.", T.dim)
      o("Only do it on a system you trust (fresh install, or verified).", T.dim)
      local okA, digest = K.anchorManifestHash()
      if okA then
        o("Anchored: " .. tostring(digest):sub(1, 32) .. "...", T.highlight)
        o("Your boot address was preserved; changing the boot device clears it.", T.dim)
      else
        o("Anchor failed: " .. tostring(digest), T.error)
      end
      return
    end

    -- verify = FILE INTEGRITY: every file in the manifest, checked for presence,
    -- syntax (Lua), and declared hash. Distinct from `doctor` (runtime health).
    -- Only problems are printed; a clean system shows just the summary.
    o("=== File integrity (every system file vs the manifest) ===", T.title)
    o("Checking presence, syntax, and declared hashes...", T.dim)
    o("")
    -- verifySystem can still fail catastrophically (e.g. manifest module
    -- itself OOMs, or kernel.fs throws). pcall so a crash can't kill the
    -- whole shell.
    local ok, err = pcall(K.verifySystem, function(t, c) o(t, c) end)
    if not ok then
      o("verify: " .. tostring(err), T.error)
    end
    o("")
    o("This checks FILES. For runtime health (memory/power/services), run 'doctor'.", T.dim)
    o("It compares against the MANIFEST. To catch a file that changed since you", T.dim)
    o("knew the system was good — and to put it back — use 'srm scan' / 'srm repair'.", T.dim)
  end

  -- FEAT-7 / FEAT-9 — package manager command.
  -- Subcommands:
  --   pkg list                         installed packages
  --   pkg search                       packages available in any repo / mount
  --   pkg info <name>                  manifest details
  --   pkg outdated                     installed packages with a newer version
  --   pkg upgrade <name>… | --all      replace with the newer version, keeping
  --                                    enable state + the rc boot marker
  --   pkg install <name> [<name>…]     resolve deps + install across all sources
  --   pkg install-dir <dir>            install a single source dir explicitly
  --   pkg install (no arg)             open the full-screen picker (menu);
  --                                    add --prompts for the classic y/N scan
  --   pkg from-floppy                  alias for the no-arg install
  --   ── automation (no picker, no prompts) ──
  --   pkg install --all --yes          every package on inserted media/repos
  --   pkg install <names…> --dry-run   print the plan, change nothing
  --   (--yes is REQUIRED by --all: a script must not hang on a question,
  --    and --all pulls in every package on whatever disk happens to be in)
  --   pkg make-disk <mount> [name…]    build an Optional Utilities disk from
  --                                    installed add-ons (parity with deploy)
  --   pkg uninstall <name>             remove an installed package
  C.pkg = function(args, o)
    if not adminOnly(o) then return end
    local okP, pkgMod = pcall(require, "kernel.pkg")
    if not okP or not pkgMod then o("pkg module unavailable", T.error); return end
    local sub = args[1]

    if not sub or sub == "list" then
      local list = pkgMod.list()
      if #list == 0 then o("No packages installed.", T.dim); return end
      o(string.format(" %-24s %-10s %s", "name", "version", "kind"), T.title)
      for _, m in ipairs(list) do
        o(string.format(" %-24s %-10s %s",
          m.name:sub(1, 24),
          (m.version or "?"):sub(1, 10),
          m.kind or "?"), T.fg)
      end

    elseif sub == "search" or sub == "available" then
      local list = pkgMod.listAllAvailable()
      if #list == 0 then
        o("No packages available in any configured repo or mounted media.", T.dim)
        o("Looked under: /usr/repo, /var/repo, /mnt/*", T.dim)
        return
      end
      -- Group the listing by category so `pkg search` reads the same way
      -- the picker does. listAllAvailable comes name-sorted; bucket it.
      table.sort(list, function(a, b)
        if (a.category or "misc") ~= (b.category or "misc") then
          return (a.category or "misc") < (b.category or "misc")
        end
        return (a.name or "") < (b.name or "")
      end)
      o(string.format(" %-20s %-10s %s", "name", "version", "source"), T.title)
      local lastCat = nil
      for _, e in ipairs(list) do
        local cat = e.category or "misc"
        if cat ~= lastCat then lastCat = cat; o("  [" .. cat .. "]", T.dim) end
        o(string.format(" %-20s %-10s %s",
          (e.name or "?"):sub(1, 20),
          (e.version or "?"):sub(1, 10),
          tostring(e.root or "?")), T.fg)
      end

    -- ── Publisher signatures ───────────────────────────────────────
    -- The trust store answers "whose packages does this machine accept".
    -- Everything that CHANGES it goes through pkgMod, which owns the
    -- admin gate; this branch is presentation.
    elseif sub == "trust" then
      local act = (args[2] or "list"):lower()
      if act == "list" then
        local keys = pkgMod.trustList()
        if #keys == 0 then
          o("No publisher keys are trusted on this machine.", T.dim)
          o("Every package therefore reads as unsigned or as signed-by-an-", T.dim)
          o("unknown-key, and your admin privilege is the only gate.", T.dim)
          o("Add one:  pkg trust add <name> <64-hex-key>", T.dim)
        else
          o(string.format(" %-16s %s", "name", "fingerprint"), T.title)
          for _, k in ipairs(keys) do
            o(string.format(" %-16s %s", k.label:sub(1, 16), k.fingerprint), T.fg)
          end
          o("", T.dim)
          o("Compare a fingerprint with the publisher over a channel that is", T.dim)
          o("NOT the disk it came on. A key that arrives with the package it", T.dim)
          o("signs proves nothing at all.", T.dim)
        end
        o(string.format("Unsigned packages are currently %s.",
          pkgMod.trustRequired() and "REFUSED" or "allowed (admin gate only)"),
          pkgMod.trustRequired() and T.highlight or T.dim)

      elseif act == "add" then
        if not (args[3] and args[4]) then
          o("Usage: pkg trust add <name> <64-hex-public-key>", T.dim)
          o("<name> is YOUR label for the publisher — it is how you will", T.dim)
          o("refer to them locally, and has nothing to do with whatever", T.dim)
          o("name their disk claims.", T.dim)
          return
        end
        local ok2, err = pkgMod.trustAdd(args[3], args[4], { session = S and S.session })
        if not ok2 then o("Refused: " .. tostring(err), T.error); return end
        o("Trusted '" .. args[3] .. "'.", T.highlight)
        o("Packages signed by this key will now install without a fresh", T.dim)
        o("judgement call. That is the point, and the cost.", T.dim)

      elseif act == "remove" or act == "rm" then
        if not args[3] then o("Usage: pkg trust remove <name>", T.dim); return end
        local ok2, err = pkgMod.trustRemove(args[3], { session = S and S.session })
        if not ok2 then o("Refused: " .. tostring(err), T.error); return end
        o("Removed '" .. args[3] .. "'. Already-installed packages are", T.highlight)
        o("unaffected — this changes what will be accepted from now on.", T.dim)

      elseif act == "require" then
        local val = (args[3] or ""):lower()
        if val ~= "on" and val ~= "off" then
          o("Usage: pkg trust require on|off", T.dim)
          o("`on` refuses unsigned packages outright. Consider what is on", T.dim)
          o("your Optional Utilities disks before turning it on.", T.dim)
          return
        end
        local ok2, err = pkgMod.trustRequire(val == "on", { session = S and S.session })
        if not ok2 then o("Refused: " .. tostring(err), T.error); return end
        o("Unsigned packages are now " .. (val == "on" and "REFUSED." or "allowed."), T.highlight)

      elseif act == "key" then
        -- Print the public key a passphrase signs as, WITHOUT signing
        -- anything: a publisher needs to hand out their key before they
        -- have a package to hand out with it.
        --
        -- #SEC — the ARGUMENT is the publisher label, which is public and
        -- belongs on the command line. The passphrase is read masked,
        -- like `pkg sign`. It used to be argv, where it sat in plain
        -- S.cmdHistory for anyone at this seat to recall with Up-arrow,
        -- and was echoed across the screen as it was typed.
        if not args[3] then
          o("Usage: pkg trust key <publisher-label>", T.dim)
          o("Prints the public key you sign as under that label, and asks", T.dim)
          o("for the passphrase without echoing it. Publish the key; never", T.dim)
          o("the passphrase. The label is part of the key: the same", T.dim)
          o("passphrase under a different label is a different identity.", T.dim)
          return
        end
        if args[4] then
          -- Almost certainly the old form, `pkg trust key <passphrase>`
          -- with a passphrase containing a space. Refuse rather than
          -- guess: deriving from the wrong string prints a key that is
          -- not theirs, and they would publish it.
          o("Too many arguments. Only the publisher label goes here — the", T.error)
          o("passphrase is asked for separately, and must never be typed", T.dim)
          o("on the command line where it is echoed and recalled.", T.dim)
          return
        end
        if not promptInput then
          o("This needs an interactive prompt for the passphrase.", T.error)
          return
        end
        local pass = promptInput("Signing passphrase: ", 96, true)
        if not pass or pass == "" then o("Aborted.", T.dim); return end
        local key, err = pkgMod.signingKey(pass, args[3])
        if not key then o(tostring(err), T.error); return end
        o(key, T.highlight)
        local okS, ps = pcall(require, "kernel.pkgsign")
        if okS and ps then
          o("fingerprint " .. ps.fingerprint(key), T.dim)
          o("signing as '" .. tostring(ps.normalizeLabel(args[3])) .. "'", T.dim)
        end

      else
        o("Usage: pkg trust [list|add|remove|require|key] ...", T.dim)
      end

    elseif sub == "verify-sig" or sub == "checksig" then
      if not args[2] then
        o("Usage: pkg verify-sig <directory>", T.dim)
        o("Says who signed a package WITHOUT installing it.", T.dim)
        return
      end
      local verdict, mOrErr = pkgMod.checkSignature(args[2])
      if not verdict then o(tostring(mOrErr), T.error); return end
      o("Package: " .. tostring(mOrErr and mOrErr.name or "?"), T.title)
      local okS, ps = pcall(require, "kernel.pkgsign")
      if okS and ps then
        for _, line in ipairs(ps.describe(verdict)) do
          o(line, verdict.state == "trusted" and T.highlight
            or (verdict.state == "invalid" and T.error or T.warning))
        end
      end

    elseif sub == "sign" then
      if not args[2] then
        o("Usage: pkg sign <directory> --as <publisher-name>", T.dim)
        o("Signs the package's manifest with a key derived from a", T.dim)
        o("passphrase you will be asked for. The signature covers the", T.dim)
        o("MANIFEST, which covers the file hashes, which cover the files —", T.dim)
        o("so sign AFTER the hashes are final, not before.", T.dim)
        return
      end
      local signerName
      for i = 3, #args do
        if args[i] == "--as" then signerName = args[i + 1] end
      end
      -- #SEC — `--as` is REQUIRED because it salts the key. It used to be
      -- optional decoration recorded in the signature; omitting it now
      -- would derive a different key from the same passphrase, so a
      -- publisher who forgot the flag once would sign as a second,
      -- untrusted identity and have no way to tell from the output.
      if not signerName or signerName == "" then
        o("Usage: pkg sign <directory> --as <publisher-name>", T.error)
        o("--as is required: the label salts your signing key, so the same", T.dim)
        o("passphrase under a different label is a different identity.", T.dim)
        o("Use the same label every time — it is part of who you are.", T.dim)
        return
      end
      -- The passphrase is read MASKED (promptInput's third argument) and
      -- passed straight through: never written to disk, never logged,
      -- never taken from the command line — an argv passphrase would end
      -- up in shell history, which is a file.
      if not promptInput then
        o("Signing needs an interactive prompt for the passphrase.", T.error)
        return
      end
      local pass = promptInput("Signing passphrase: ", 96, true)
      if not pass or pass == "" then
        o("Aborted. A signing passphrase is required (12+ characters).", T.dim)
        o("It IS the private key — the same passphrase always produces the", T.dim)
        o("same key, on any machine, so make it long and keep it.", T.dim)
        return
      end
      local key, sigPathOrErr = pkgMod.signPackage(args[2], pass,
        { session = S and S.session, signer = signerName })
      if not key then o("Signing failed: " .. tostring(sigPathOrErr), T.error); return end
      o("Signed. Wrote " .. tostring(sigPathOrErr), T.highlight)
      o("public key " .. key, T.fg)
      local okS2, ps2 = pcall(require, "kernel.pkgsign")
      if okS2 and ps2 then o("fingerprint " .. ps2.fingerprint(key), T.dim) end

    -- ── Remote repositories (internet card) ────────────────────────
    elseif sub == "repo" or sub == "repos" then
      local act = (args[2] or "list"):lower()
      if act == "list" then
        local list = pkgMod.repos()
        if #list == 0 then
          o("No remote repositories configured.", T.dim)
          o("Add one:  pkg repo add <name> <https://host/path>", T.dim)
          o("The URL is the directory holding the repo's programs.cfg.", T.dim)
          return
        end
        o(string.format(" %-14s %s", "name", "url"), T.title)
        for _, r in ipairs(list) do
          o(string.format(" %-14s %s", r.name:sub(1, 14), r.url), T.fg)
          if r.description then o("                " .. r.description, T.dim) end
        end
        o("", T.dim)
        o("This list is the allowlist — nothing else is fetched.", T.dim)
      elseif act == "add" then
        if not args[3] or not args[4] then
          o("Usage: pkg repo add <name> <url> [description]", T.dim)
          o("  url = the directory containing programs.cfg", T.dim)
          return
        end
        local desc = #args >= 5 and table.concat(args, " ", 5) or nil
        local ok2, err2 = pkgMod.addRepo(args[3], args[4], desc, { session = helpers.sessionOf(S) })
        if ok2 then
          o("Repo '" .. args[3] .. "' added.", T.highlight)
          o("It is now an accepted source of executable code for this", T.warning)
          o("machine. 'pkg repo remove " .. args[3] .. "' undoes that.", T.warning)
        else o(tostring(err2), T.error) end
      elseif act == "remove" or act == "rm" then
        if not args[3] then o("Usage: pkg repo remove <name>", T.dim); return end
        local ok2, err2 = pkgMod.removeRepo(args[3], { session = helpers.sessionOf(S) })
        if ok2 then o("Repo '" .. args[3] .. "' removed.", T.highlight)
        else o(tostring(err2), T.error) end
      else
        o("Usage: pkg repo [list|add <name> <url>|remove <name>]", T.dim)
      end

    elseif sub == "remote" then
      -- What the configured repos have to offer.
      local inetOk = _G._TOS and _G._TOS.internet
      if inetOk and not inetOk.available() then
        o(inetOk.status().reason or "internet is not available", T.warning)
        o("'internet' shows the details.", T.dim)
        return
      end
      o("Contacting configured repositories...", T.dim)
      local list = pkgMod.searchRemote({ refresh = args[2] == "--refresh" })
      if #list == 0 then
        o("Nothing available. Check 'pkg repo list'.", T.dim); return
      end
      o(string.format(" %-22s %-10s %s", "name", "version", "repo"), T.title)
      for _, e in ipairs(list) do
        o(string.format(" %-22s %-10s %s",
          (e.name or "?"):sub(1, 22), (e.version or "-"):sub(1, 10),
          tostring(e.repo)), T.fg)
        if e.description then o("   " .. tostring(e.description):sub(1, 60), T.dim) end
      end
      o("", T.dim)
      o("Install one with:  pkg fetch <name>", T.dim)

    elseif sub == "fetch" then
      if not args[2] then
        o("Usage: pkg fetch <name> [--allow-unverified]", T.dim)
        o("Downloads from a configured repo, then installs it.", T.dim)
        return
      end
      local allow = false
      for i = 3, #args do
        if args[i] == "--allow-unverified" then allow = true end
      end
      o("Fetching '" .. args[2] .. "'...", T.dim)
      local ok2, res = pkgMod.installRemote(args[2], {
        session = helpers.sessionOf(S), allowUnverified = allow,
      })
      if ok2 then
        o(string.format("Installed '%s' from repo '%s' (%d files, %d bytes).",
          args[2], tostring(res and res.repo), (res and res.files) or 0,
          (res and res.bytes) or 0), T.highlight)
      else
        o(tostring(res), T.error)
        -- The single most likely refusal, and the one worth explaining
        -- rather than leaving as a bare error string.
        if tostring(res):find("hash", 1, true)
           or tostring(res):find("unverified", 1, true) then
          o("", T.dim)
          o("That repo ships no file hashes, so TOS cannot check what it", T.dim)
          o("sent. Re-run with --allow-unverified if you trust it.", T.dim)
        end
      end

    elseif sub == "outdated" or sub == "updates" then
      local list = pkgMod.outdated()
      if #list == 0 then
        o("Everything is up to date (against what's mounted right now).", T.highlight)
        o("Insert another disk and re-run to check against it too.", T.dim)
        return
      end
      o(string.format(" %-20s %-10s %-10s %s", "name", "installed", "available", "from"), T.title)
      for _, u in ipairs(list) do
        o(string.format(" %-20s %-10s %-10s %s", u.name:sub(1, 20),
          tostring(u.from):sub(1, 10), tostring(u.to):sub(1, 10),
          tostring(u.root or "?")), T.fg)
      end
      o("", T.dim)
      o("pkg upgrade <name>   or   pkg upgrade --all --yes", T.dim)

    elseif sub == "upgrade" then
      local wantAll, assumeYes, force, dryRun = false, false, false, false
      local names = {}
      for i = 2, #args do
        local a = tostring(args[i])
        if a == "--all" then wantAll = true
        elseif a == "--yes" or a == "-y" then assumeYes = true
        elseif a == "--force" then force = true
        elseif a == "--dry-run" or a == "--dryrun" then dryRun = true
        elseif a:sub(1, 2) ~= "--" then names[#names + 1] = a end
      end

      local todo = {}
      if wantAll then
        for _, u in ipairs(pkgMod.outdated()) do todo[#todo + 1] = u end
      elseif #names > 0 then
        -- Named packages are upgraded even when `outdated` didn't list
        -- them, so `--force` can still drive a re-install or a downgrade.
        local avail = {}
        for _, u in ipairs(pkgMod.outdated()) do avail[u.name] = u end
        for _, n in ipairs(names) do
          todo[#todo + 1] = avail[n] or { name = n, from = "?", to = "?" }
        end
      else
        o("Usage: pkg upgrade <name>… | --all [--yes] [--force] [--dry-run]", T.dim)
        o("       pkg outdated   shows what has a newer version available", T.dim)
        return
      end

      if #todo == 0 then
        o("Nothing to upgrade.", T.highlight); return
      end
      if dryRun then
        o(string.format("Would upgrade %d package(s):", #todo), T.title)
        for _, u in ipairs(todo) do
          o(string.format("  %-20s %s -> %s", u.name, tostring(u.from), tostring(u.to)), T.fg)
        end
        o("(--dry-run: nothing was changed)", T.dim)
        return
      end
      -- An upgrade REPLACES running code, so --all needs the same explicit
      -- confirmation `install --all` does.
      if wantAll and not assumeYes then
        o(string.format("--all would upgrade %d package(s):", #todo), T.warning)
        for _, u in ipairs(todo) do
          o(string.format("  %-20s %s -> %s", u.name, tostring(u.from), tostring(u.to)), T.fg)
        end
        o("Add --yes to proceed.", T.dim)
        return
      end

      local okN, failN = 0, 0
      for _, u in ipairs(todo) do
        local ok2, res = pkgMod.upgrade(u.name,
          { session = helpers.sessionOf(S), force = force })
        if ok2 then
          okN = okN + 1
          o(string.format("  %-20s %s -> %s", u.name, tostring(res.from), tostring(res.to)),
            T.highlight)
          if res.dropped and #res.dropped > 0 then
            o(string.format("      %d file(s) no longer shipped, removed", #res.dropped), T.dim)
          end
          if res.enabled == false then
            o("      (was disabled; left disabled)", T.dim)
          end
        else
          failN = failN + 1
          o(string.format("  %-20s FAILED: %s", u.name, tostring(res)), T.error)
        end
      end
      o(string.format("%d upgraded, %d failed.", okN, failN),
        failN > 0 and T.warning or T.highlight)
      if okN > 0 then
        o("Services keep their enabled/disabled state; restart them to run the", T.dim)
        o("new code ('service stop <svc>' then 'service start <svc>').", T.dim)
      end

    elseif sub == "info" then
      if not args[2] then o("Usage: pkg info <name>", T.dim); return end
      local m = pkgMod.info(args[2])
      if not m then o("Not installed: " .. args[2], T.error); return end
      o(string.format(" name:        %s", m.name), T.title)
      o(string.format(" version:     %s", m.version or "?"), T.fg)
      o(string.format(" kind:        %s", m.kind or "?"), T.fg)
      if m.category then o(string.format(" category:    %s", m.category), T.fg) end
      if m.description then o(string.format(" description: %s", m.description), T.fg) end
      if m.author then o(string.format(" author:      %s", m.author), T.fg) end
      o(string.format(" status:      %s", pkgMod.isEnabled(m.name) and "enabled" or "disabled"),
        pkgMod.isEnabled(m.name) and T.highlight or T.dim)
      if type(m.commands) == "table" then
        local cnames = {}
        for cn in pairs(m.commands) do cnames[#cnames + 1] = cn end
        if #cnames > 0 then table.sort(cnames); o(" commands:    " .. table.concat(cnames, ", "), T.fg) end
      end
      if m.requires and #m.requires > 0 then
        o(" requires:", T.fg)
        for _, r in ipairs(m.requires) do
          local n, c
          if type(r) == "table" then n, c = r.name, r.version
          else n, c = r:match("^(%S+)%s*(.*)$") end
          o(string.format("   %s %s", n, c or ""), T.dim)
        end
      end
      if m.provides and #m.provides > 0 then
        o(" provides:    " .. table.concat(m.provides, ", "), T.fg)
      end
      if m.recommends and #m.recommends > 0 then
        o(" recommends:  " .. table.concat(m.recommends, ", "), T.dim)
      end
      if m.conflicts and #m.conflicts > 0 then
        o(" conflicts:   " .. table.concat(m.conflicts, ", "), T.warning)
      end
      -- Provenance. A package written for OpenOS runs here on the compat
      -- layer, and if its manifest declared no capabilities it was granted
      -- the compat surface at install time — a real privilege grant the
      -- operator is entitled to SEE rather than infer.
      if m.origin == "openos" then
        o(" origin:      OpenOS/OPPM package (runs on the compat layer)", T.warning)
        if m.capsFromCompat then
          o("              declared no capabilities — granted: "
            .. table.concat(m.capabilities or {}, ", "), T.warning)
        end
      end
      -- Who signed it, recorded at install time from a real verification.
      -- Two separate facts, deliberately shown separately: `signature`
      -- says whether the bytes are attributable to a key, `integrity`
      -- says whether the files matched their declared hashes. A package
      -- can have either without the other and an operator should be able
      -- to see which they have.
      do
        local st = m._sigState or "unsigned"
        if st == "trusted" then
          o(string.format(" signature:   signed by trusted publisher '%s'", tostring(m._sigLabel)), T.highlight)
        elseif st == "unknown" then
          o(" signature:   valid, but the key was not trusted at install time", T.warning)
        else
          o(" signature:   none (unsigned)", T.dim)
        end
        if m._sigKey then
          local okS, ps = pcall(require, "kernel.pkgsign")
          local fp = (okS and ps and ps.fingerprint) and ps.fingerprint(m._sigKey) or m._sigKey:sub(1, 16)
          o("              key " .. fp, T.dim)
        end
        o(string.format(" integrity:   %s", m._unverified
          and "NOT verified (installed with --allow-unverified)"
          or "all files matched their declared hashes"),
          m._unverified and T.warning or T.dim)
      end

    elseif sub == "install" or sub == "install-dir" or sub == "from-floppy" or sub == "fromfloppy" then
      -- One smart verb (v1.4.0): `pkg install` reads what you gave it.
      --   • no argument            → scan mounted media, confirm each
      --                              (the old `from-floppy`)
      --   • a path (has a "/")      → install that directory
      --                              (the old `install-dir`)
      --   • a bare name             → install by name, resolving deps
      -- `install-dir` / `from-floppy` still work as hidden aliases so no
      -- muscle memory or saved menu entry breaks.
      -- #SEC — packages without a full hash set are rejected unless the
      -- operator passes --allow-unverified (runs untrusted code with no
      -- integrity check). Scan for the flag once; `target` skips it.
      --
      -- AUTOMATION FLAGS. The picker is for a person at a keyboard; a
      -- startup script, a `bg` job or a cluster provisioning step needs to
      -- install without one, and needs to be able to find out what WOULD
      -- happen first. All of them are position-independent, and names may
      -- be given in any number:
      --   --all           every package available on inserted media/repos
      --   --yes / -y      never prompt (required by --all, since the
      --                   alternative is a script that hangs on a question
      --                   nobody is there to answer)
      --   --dry-run       print the plan, change nothing
      local allowUnverified, wantAll, assumeYes, dryRun = false, false, false, false
      local names = {}
      for i = 2, #args do
        local a = tostring(args[i])
        if a == "--allow-unverified" then allowUnverified = true
        elseif a == "--all" then wantAll = true
        elseif a == "--yes" or a == "-y" then assumeYes = true
        elseif a == "--dry-run" or a == "--dryrun" then dryRun = true
        elseif a == "--key" then                       -- consumed with its value
        elseif args[i - 1] == "--key" then             -- the value itself
        elseif a:sub(1, 2) ~= "--" then names[#names + 1] = a end
      end
      local target = names[1]
      local function looksLikePath(s)
        return type(s) == "string" and s:find("/", 1, true) ~= nil
      end
      local mode
      if wantAll then mode = "all"
      elseif sub == "install-dir" then mode = "dir"
      elseif sub == "from-floppy" or sub == "fromfloppy" then mode = "floppy"
      elseif not target then mode = "floppy"
      elseif looksLikePath(target) then mode = "dir"
      elseif #names > 1 then mode = "many"
      else mode = "name" end

      -- Shared driver for the non-interactive modes.
      local function installList(list)
        if #list == 0 then o("Nothing to install.", T.dim); return end
        if dryRun then
          o(string.format("Would install %d package(s):", #list), T.title)
          for _, n in ipairs(list) do o("  " .. n, T.fg) end
          o("(--dry-run: nothing was changed)", T.dim)
          return
        end
        local okN, failN = 0, 0
        for _, n in ipairs(list) do
          local ok2, summary = pkgMod.installByName(n,
            { session = helpers.sessionOf(S), allowUnverified = allowUnverified })
          if ok2 then
            okN = okN + 1
            o(string.format("  %-20s installed%s", n,
              (#summary.skipped > 0)
                and (" (deps present: " .. table.concat(summary.skipped, ", ") .. ")")
                or ""), T.highlight)
          else
            failN = failN + 1
            o(string.format("  %-20s FAILED: %s", n, tostring(summary)), T.error)
          end
        end
        o(string.format("%d installed, %d failed.", okN, failN),
          failN > 0 and T.warning or T.highlight)
      end

      if mode == "all" then
        -- #SEC — --all installs every package it can see, which on a
        -- machine with unknown media inserted is a lot of third-party code.
        -- Require the explicit --yes so it can never happen from a typo.
        if not (assumeYes or dryRun) then
          o("--all installs EVERY package on every inserted disk and repo.", T.warning)
          o("Add --yes to confirm, or --dry-run to see the list first.", T.dim)
          return
        end
        local list = {}
        for _, e in ipairs(pkgMod.listAllAvailable() or {}) do
          if not (pkgMod.info and pkgMod.info(e.name)) then list[#list + 1] = e.name end
        end
        table.sort(list)
        installList(list)
        return
      elseif mode == "many" then
        installList(names)
        return
      end

      if mode == "name" then
        -- FEAT-14 — pick up an optional --key arg.
        local licenseKey
        for i = 3, #args do
          if args[i] == "--key" and args[i + 1] then licenseKey = args[i + 1] end
        end
        local ok2, summary = pkgMod.installByName(target,
          { licenseKey = licenseKey, session = helpers.sessionOf(S),
            allowUnverified = allowUnverified })  -- #SEC CR-5 + hash gate
        if ok2 then
          o(string.format("Installed: %s", table.concat(summary.installed, ", ")), T.highlight)
          if #summary.skipped > 0 then
            o(string.format("Skipped (already present): %s",
              table.concat(summary.skipped, ", ")), T.dim)
          end
        else
          o("Install failed: " .. tostring(summary), T.error)
        end

      elseif mode == "dir" then
        if not target then o("Usage: pkg install <dir>", T.dim); return end
        local ok2, info = pkgMod.install(target,
          { session = helpers.sessionOf(S), allowUnverified = allowUnverified })  -- #SEC CR-5
        if ok2 then o("Installed: " .. tostring(info), T.highlight)
        else o("Install failed: " .. tostring(info), T.error) end

      else  -- floppy / no-arg: prefer the full-screen picker, fall back to prompts
        -- Prefer the Optional Utilities TUI picker (the same installer
        -- that ships on the disk) over the sequential y/N prompts —
        -- unless the operator forces the classic path with --prompts, or
        -- the picker can't run (no GPU / load error), in which case we
        -- drop through to installFromFloppy below.
        local forcePrompts = false
        for i = 2, #args do
          if args[i] == "--prompts" or args[i] == "--classic" then forcePrompts = true end
        end
        local ranPicker = false
        if not forcePrompts and pkgMod.runInstaller then
          local okR, why = pkgMod.runInstaller({ session = helpers.sessionOf(S) })
          if okR then
            ranPicker = true
            -- #FIX (emulator round 7) — DROP THE SHADOW FIRST. The picker
            -- draws through a raw GPU proxy, straight past this seat's
            -- dirty-cell shadow buffer, so the shadow still believes the
            -- old shell screen is on the GPU. drawAll then elides every
            -- cell it thinks is unchanged and the operator is left with a
            -- half-painted shell — observed as a file list of icons with
            -- no filenames or sizes. Same hazard executor.lua already
            -- handles for sandboxed package commands (`foreignDraw`);
            -- `pkg install` is a BUILT-IN, so it never went through that.
            if S.D and S.D.invalidate then pcall(S.D.invalidate) end
            if deps.drawAll then pcall(deps.drawAll) end  -- picker owned the screen
          elseif why then
            -- Not fatal: fall back to the prompt scan. Say why once so a
            -- headless/GPU-less operator understands the downgrade.
            o("Menu installer unavailable (" .. tostring(why)
              .. ") — using prompts.", T.dim)
          end
        end
        if ranPicker then return end

        -- Classic path: scan every mount, prompt per package (y/N).
        local ok2, summary = pkgMod.installFromFloppy({
          session = helpers.sessionOf(S),  -- #SEC CR-5
          allowUnverified = allowUnverified,
          confirm = function(name, dir)
            if not promptInput then return false end
            -- Name the DISK, not the nested repo path (an over-long path
            -- pushed the "[y/N]:" affordance off an 80-column screen).
            local disk = dir:match("^(/mnt/[^/]+)") or dir
            local typed = promptInput("Install " .. name .. " from " .. disk .. "? [y/N]: ", 4) or ""
            return typed:lower() == "y" or typed:lower() == "yes"
          end,
        })
        if ok2 then
          if #summary.installed > 0 then
            o(string.format("Installed from media: %s",
              table.concat(summary.installed, ", ")), T.highlight)
          end
          if #summary.skipped > 0 then
            o(string.format("Skipped: %s", table.concat(summary.skipped, ", ")), T.dim)
          end
          if #summary.installed == 0 and #summary.skipped == 0 then
            o("No packages found on mounted media. Insert a package disk and retry.", T.dim)
          end
        else
          o("Media scan failed: " .. tostring(summary), T.error)
        end
      end

    elseif sub == "license-hash" then
      -- FEAT-14 — helper for package authors. Pass <name> + <key>;
      -- print the 64-hex string they should put in license.keys[].
      if not args[2] or not args[3] then
        o("Usage: pkg license-hash <package-name> <license-key>", T.dim); return
      end
      local h, lhErr = pkgMod.computeLicenseHash(args[2], args[3])
      if h then o(h, T.fg)
      else o("Error: " .. tostring(lhErr), T.error) end

    elseif sub == "uninstall" or sub == "remove" then
      if not args[2] then o("Usage: pkg uninstall <name>", T.dim); return end
      local ok2, info = pkgMod.uninstall(args[2], { session = helpers.sessionOf(S) })  -- #SEC CR-5
      if ok2 then o("Uninstalled: " .. args[2], T.highlight)
      else o("Uninstall failed: " .. tostring(info), T.error) end

    elseif sub == "make-disk" or sub == "export-disk" then
      -- In-TOS Optional Utilities builder: assemble installed add-ons into a
      -- pick-and-choose disk (parity with `deploy`, which builds a whole-OS
      -- image). No dev box / TOS-Extras source tree required.
      if not args[2] then
        o("Usage: pkg make-disk <mount> [name ...]", T.dim)
        o("  Builds an Optional Utilities disk from your INSTALLED add-ons so", T.dim)
        o("  you can install them on another TOS machine without a dev box.", T.dim)
        o("  Name args limit the export; omit to include every add-on.", T.dim)
        o("  e.g. pkg make-disk /mnt/floppy", T.dim)
        return
      end
      if not pkgMod.exportDisk then o("This TOS build has no make-disk support.", T.error); return end
      local only = nil
      if args[3] then only = {}; for i = 3, #args do only[#only + 1] = args[i] end end
      local ok2, summary = pkgMod.exportDisk(args[2],
        { only = only, session = helpers.sessionOf(S) })  -- #SEC CR-5
      if ok2 then
        o(string.format("Built add-on disk on %s: %d package(s), %d file(s)",
          summary.target, #summary.packages, summary.files), T.highlight)
        if #summary.packages > 0 then
          o("  " .. table.concat(summary.packages, ", "), T.fg)
        end
        if #summary.problems > 0 then
          o("  Warnings:", T.warning)
          for _, p in ipairs(summary.problems) do o("   ! " .. p, T.warning) end
        end
        o("On the target machine, insert the disk and run "
          .. summary.target .. "/install.lua", T.dim)
      else
        o("make-disk failed: " .. tostring(summary), T.error)
      end

    elseif sub == "enable" or sub == "disable" then
      -- Folded in from the retired `mod` command (the legacy module manager was
      -- replaced by pkg in v1.3.1): toggle an installed package on/off without
      -- uninstalling it. A disabled package's commands/services stay dormant.
      if not args[2] then o("Usage: pkg " .. sub .. " <name>", T.dim); return end
      local on = (sub == "enable")
      local ok2, err = pkgMod.setEnabled(args[2], on, { session = helpers.sessionOf(S) })  -- #SEC CR-5
      if ok2 then o((on and "Enabled: " or "Disabled: ") .. args[2], T.highlight)
      else o("Failed: " .. tostring(err), T.error) end

    elseif sub == "commands" then
      -- Which shell commands the installed packages currently provide.
      local cmds = pkgMod.commands()
      local names = {}
      for n in pairs(cmds) do names[#names + 1] = n end
      if #names == 0 then o("No commands provided by installed packages.", T.dim); return end
      table.sort(names)
      o("Commands provided by packages:", T.title)
      for _, n in ipairs(names) do o("  " .. n, T.fg) end

    else
      o("Usage: pkg [list | search | info <name> | install [name|dir] | uninstall <name>", T.dim)
      o("           | enable <name> | disable <name> | commands | make-disk <mnt>]", T.dim)
      o("  install: a name installs by name; a path installs that dir; no arg", T.dim)
      o("           scans mounted media. Shortcuts: 'install <name>', 'uninstall <name>'.", T.dim)
      o("  signing: trust [list|add|remove|require|key] · verify-sig <dir> · sign <dir>", T.dim)
    end
  end

  -- Top-level shortcuts that imply the package manager, so a new operator
  -- can type `install <name>` without knowing the manager is called `pkg`.
  -- They just prepend the subcommand and route through C.pkg (which does
  -- the admin gate + all the work). Registered as aliases of `pkg` so they
  -- collapse onto its help row rather than adding their own.
  C.install = function(args, o)
    local a = { "install" }
    for i = 1, #(args or {}) do a[#a + 1] = args[i] end
    return C.pkg(a, o)
  end
  C.uninstall = function(args, o)
    local a = { "uninstall" }
    for i = 1, #(args or {}) do a[#a + 1] = args[i] end
    return C.pkg(a, o)
  end

  -- FEAT-6 — backup/restore command.
  -- Subcommands:
  --   backup snapshot <src> <dest.bak>   create a snapshot file
  --   backup inspect  <file.bak>         show header info
  --   backup restore  <file.bak> [dest]  restore (force= --force)
  C.backup = function(args, o)
    if not adminOnly(o) then return end
    local bmod = _G._TOS and _G._TOS.backup
    if not bmod then o("backup module unavailable", T.error); return end
    local sub = args[1]
    local sess = helpers.sessionOf(S)  -- #SEC CR-9 — seat-bound principal

    if sub == "snapshot" or sub == "create" then
      if not args[2] or not args[3] then
        o("Usage: backup snapshot <src> <dest.bak>", T.dim); return
      end
      local ok2, summary = bmod.snapshot(args[2], args[3], { session = sess })
      if ok2 then
        o(string.format("Snapshot OK: %d entries, %d bytes -> %s",
          summary.entries, summary.bytes, args[3]), T.highlight)
        o("  metaHash: " .. summary.hash:sub(1, 16) .. "...", T.dim)
      else
        o("Snapshot failed: " .. tostring(summary), T.error)
      end

    elseif sub == "inspect" then
      if not args[2] then o("Usage: backup inspect <file.bak>", T.dim); return end
      local info, err = bmod.inspect(args[2], { session = sess })
      if not info then o("Inspect failed: " .. tostring(err), T.error); return end
      o(string.format(" magic:    %s", info.magic), T.fg)
      o(string.format(" created:  %d", info.created), T.fg)
      o(string.format(" entries:  %d", info.entries), T.fg)
      o(string.format(" root:     %s", info.root), T.fg)
      o(string.format(" metaHash: %s...", info.metaHash:sub(1, 24)), T.fg)
      o(string.format(" size:     %d bytes", info.size), T.fg)

    elseif sub == "restore" then
      if not args[2] then
        o("Usage: backup restore <file.bak> [destRoot] [--force]", T.dim); return
      end
      local destRoot, force = nil, false
      for i = 3, #args do
        if args[i] == "--force" or args[i] == "-f" then force = true
        else destRoot = args[i] end
      end
      local ok2, summary = bmod.restore(args[2],
        { session = sess, destRoot = destRoot, force = force })
      if ok2 then
        o(string.format("Restore OK: %d/%d files -> %s",
          summary.restored, summary.entries, summary.destRoot), T.highlight)
        refreshBrowser()
      else
        o("Restore failed: " .. tostring(summary), T.error)
      end

    else
      o("Usage: backup [snapshot|inspect|restore] ...", T.dim)
      o("  backup snapshot <src> <dest.bak>", T.dim)
      o("  backup inspect  <file.bak>", T.dim)
      o("  backup restore  <file.bak> [destRoot] [--force]", T.dim)
    end
  end

  -- FEAT-4 — launch kiosk mode for the current shell. Admin-only:
  -- starting kiosk for yourself doesn't make sense unless you're an
  -- operator testing the config, and a non-admin shouldn't be able to
  -- demote themselves into kiosk and then claim the shell is "broken".
  C.kiosk = function(args, o)
    if not adminOnly(o) then return end
    local okK, kioskMod = pcall(require, "shell.kiosk")
    if not okK or not kioskMod then o("kiosk module unavailable", T.error); return end
    o("Kiosk = the LOCKED, guest-facing menu (allow-list + read-only).", T.title)
    -- We can't cleanly hand the panels shell over to kiosk in-place
    -- (panels owns the event loop). Suggest the operator log out and
    -- log back in as the kiosk user, which is the supported path.
    o("To test: log out, log in as the 'kiosk' user.", T.dim)
    o("Config: /etc/kiosk.cfg", T.dim)
    o("", T.fg)
    o("Looking for the OPERATOR multi-tool? Run 'launcher' — same clickable", T.highlight)
    o("menu, but it runs real commands at YOUR tier (no allow-list).", T.dim)
  end

  -- FEAT-2 — diagnostic unit. Canonical name is `doctor` (matches the
  -- "brew doctor / pacman doctor" idiom — friendlier in error
  -- messages: "run `doctor` to diagnose" reads better than "run
  -- `diag`"). `diag` is kept below as an alias.
  C.doctor = function(args, o)
    local okD, diagMod = pcall(require, "kernel.diag")
    if not okD or not diagMod then o("doctor module unavailable", T.error); return end
    local severityColor = {
      ok   = T.highlight or T.fg,
      info = T.dim       or T.fg,
      warn = T.warning   or T.fg,
      err  = T.error     or T.fg,
    }
    -- doctor = RUNTIME HEALTH: memory headroom, power state, disks, peripherals,
    -- services, users, recent log warnings, security posture, trash. Distinct
    -- from `verify` (static file integrity vs the manifest).
    local only = args[1]  -- optional: run a single section
    o("=== TOS doctor \226\128\148 runtime health ===", T.title)
    local counts = diagMod.run(function(line, sev)
      o(line, severityColor[sev] or T.fg)
    end, { only = only })
    o("", T.dim)
    local summary = string.format(
      "Summary: %d ok, %d info, %d warn, %d err",
      counts.ok, counts.info, counts.warn, counts.err)
    local sumColor = counts.err > 0 and T.error
      or counts.warn > 0 and T.warning
      or T.highlight
    o(summary, sumColor)
    o("This checks RUNTIME health. For a full file-integrity check, run 'verify'.", T.dim)
    o("'srm' runs both, plus the known-good baseline check.", T.dim)
  end
  C.diag = C.doctor  -- back-compat alias

  -- ── SRM: System Repair & Maintenance ──────────────────────────────
  -- The front door over the four maintenance tools that grew up separately:
  -- `doctor` (runtime health), `verify` (files vs the manifest), the boot
  -- fixer pass, and the known-good baseline SRM itself adds. Those commands
  -- all still work on their own — this is the one that runs them together,
  -- and the only one that can report what the EEPROM half saw when a boot
  -- failed before anything on disk could run.
  --
  -- Tier: read-only subcommands are open (a user should be able to ask why
  -- the machine is unhappy); everything that WRITES is admin-gated in-body,
  -- the same split `optimize` uses.
  C.srm = function(args, o)
    local okS, srmMod = pcall(require, "kernel.srm")
    if not okS or not srmMod then o("srm module unavailable", T.error); return end
    local SEV = {
      ok   = T.highlight or T.fg,
      info = T.dim       or T.fg,
      warn = T.warning   or T.fg,
      err  = T.error     or T.fg,
    }
    local function show(rep)
      for _, f in ipairs(rep.findings) do o(f.text, SEV[f.sev] or T.fg) end
      return rep
    end
    local function totals(rep)
      local c = rep.counts
      o("", T.dim)
      o(string.format("%d ok, %d info, %d warn, %d err%s",
        c.ok, c.info, c.warn, c.err,
        (rep.fixed or 0) > 0 and ("  |  " .. rep.fixed .. " fixed") or ""),
        SEV[srmMod.worst(rep)] or T.fg)
    end

    -- Grammar lives in the module (srm.parseArgs) so it is pure and pinned by
    -- test_srm.lua rather than trapped in this closure.
    local sub, flags, rest = srmMod.parseArgs(args)
    if flags.source == true then
      o("--source needs a mount point, e.g. --source /mnt/floppy", T.error); return
    end

    if sub == "status" then
      o("=== SRM \226\128\148 System Repair & Maintenance ===", T.title)
      totals(show(srmMod.status()))
      o("", T.dim)
      o("scan = compare files to the baseline   health = runtime   verify = manifest", T.dim)
      o("repair = fix what is safe             baseline = record a known-good system", T.dim)

    elseif sub == "health" then
      -- Same unit `doctor` runs; surfaced here so an operator working
      -- through SRM never has to leave it.
      return C.doctor(rest, o)

    elseif sub == "verify" then
      return C.verify(rest, o)

    elseif sub == "scan" then
      o("=== SRM scan \226\128\148 files vs the known-good baseline ===", T.title)
      o("Hashing every baselined file; this takes a moment.", T.dim)
      totals(show(srmMod.scan()))

    elseif sub == "baseline" then
      if not adminOnly(o) then return end
      -- #SEC — a baseline is a claim about what "good" looks like. Capturing
      -- one on an already-compromised system just certifies the damage, so
      -- say plainly what the operator is asserting before doing it.
      o("Recording what THIS system looks like right now as the known-good", T.title)
      o("baseline. Only do that on a system you trust — a fresh install, or", T.dim)
      o("one that just passed 'srm verify'. Anything already wrong becomes", T.dim)
      o("the new definition of correct.", T.dim)
      o("", T.dim)
      local withContent = flags.full and true or false
      local ok2, sum = srmMod.baseline(nil, { content = withContent })
      if not ok2 then o("Baseline failed: " .. tostring(sum), T.error); return end
      o(string.format("Baseline captured from %s: %d file(s) hashed.",
        tostring(sum.source), sum.hashed), T.highlight)
      if withContent then
        o(string.format("  %d copy(ies) stored, %.1f KB of disk.",
          sum.stored, sum.bytes / 1024), T.fg)
        o("  Local repair is now possible: 'srm repair --restore'.", T.fg)
      else
        o("  Hashes only — drift is detectable, but repair will need", T.fg)
        o("  '--source <mount>' (e.g. the install floppy). Use --full to", T.dim)
        o("  store verified copies locally instead.", T.dim)
      end
      if sum.skipped > 0 then
        o(string.format("  %d file(s) skipped (over the %d KB store cap or unreadable).",
          sum.skipped, srmMod.MAX_STORE_BYTES / 1024), T.warning)
      end
      if sum.pruned > 0 then
        o(string.format("  %d stale copy(ies) from the previous baseline removed.",
          sum.pruned), T.fg)
      end
      for _, p in ipairs(sum.missing) do
        o("  MISSING at capture time: " .. p, T.warning)
      end

    elseif sub == "restore" then
      if not adminOnly(o) then return end
      o("=== SRM restore ===", T.title)
      totals(show(srmMod.restore(nil, {
        source = type(flags.source) == "string" and flags.source or nil,
        unverified = flags.unverified and true or false,
        paths = #rest > 0 and rest or nil,
      })))

    elseif sub == "repair" then
      if not adminOnly(o) then return end
      o("=== SRM repair ===", T.title)
      if not flags.restore then
        o("Fixing what is mechanically safe (interrupted writes, stale state,", T.dim)
        o("oversized logs). Add --restore to also put back system files that", T.dim)
        o("are missing or have changed since the baseline.", T.dim)
      end
      o("", T.dim)
      totals(show(srmMod.repair(nil, {
        restore = flags.restore and true or false,
        source = type(flags.source) == "string" and flags.source or nil,
        unverified = flags.unverified and true or false,
      })))
      o("", T.dim)
      o("Some fixes only apply at boot: 'bootsettings repair on' runs this", T.dim)
      o("pass before anything reads the files it repairs.", T.dim)

    elseif sub == "full" then
      -- Everything, in the order a diagnosis actually proceeds: what
      -- happened last boot, is the hardware healthy, are the files intact,
      -- have they changed since we knew them to be good.
      o("=== SRM full report ===", T.title)
      o("", T.dim)
      o("-- status --", T.title);  show(srmMod.status())
      o("", T.dim)
      o("-- health --", T.title);  C.doctor({}, o)
      o("", T.dim)
      o("-- integrity --", T.title); C.verify({}, o)
      o("", T.dim)
      o("-- baseline --", T.title); totals(show(srmMod.scan()))

    else
      o("Usage: srm [status|scan|health|verify|repair|baseline|restore|full]", T.title)
      o("  srm                      what SRM knows right now (instant)", T.dim)
      o("  srm scan                 compare files to the known-good baseline", T.dim)
      o("  srm health               runtime health  (same as 'doctor')", T.dim)
      o("  srm verify               files vs the manifest  (same as 'verify')", T.dim)
      o("  srm full                 all of the above, in one report", T.dim)
      o("  srm baseline [--full]    record a known-good system (--full stores copies)", T.dim)
      o("  srm repair [--restore]   fix what is safe; --restore puts files back", T.dim)
      o("  srm restore [--source <mount>] [--unverified] [path...]", T.dim)
      o("", T.dim)
      o("SRM has two halves. The EEPROM one runs at POST and catches the", T.dim)
      o("faults that stop a boot; this one catches everything the EEPROM has", T.dim)
      o("no room for. 'srm status' reports what the EEPROM half saw.", T.dim)
    end
  end

  -- Disk swap status / maintenance. Viewing is harmless (any tier);
  -- `clear` wipes the shared /var/swap scratch so it is admin-gated.
  -- (v1.4.0 consolidation: the standalone `swap` command folded into
  -- `optimize swap ...` — optimize was already the front door for the
  -- swap boot-feature toggle, so status/clear/keys live there too.)

  -- Boot settings editor (the missed-the-DEL-window fallback). CLI-driven
  -- so it's robust inside the panels shell (the full modal UI is the
  -- DEL-during-boot path). Writes /etc/boot.cfg; changes apply next boot.
  C.bootsettings = function(args, o)
    if not adminOnly(o) then return end
    local okC, bootcfg = pcall(require, "kernel.bootcfg")
    if not okC or not bootcfg then o("bootcfg unavailable", T.error); return end
    local fsMod = _G._TOS and _G._TOS.fs
    if not fsMod then o("fs unavailable", T.error); return end
    local cfg = bootcfg.load(fsMod)
    local sub = (args[1] or ""):lower()

    if sub == "" or sub == "show" then
      o("=== Boot Settings (/etc/boot.cfg) ===", T.title)
      o("  profile    : " .. cfg.profile
        .. (cfg.profile == "safe" and "   (SAFE MODE)" or "   (what loads)"), T.fg)
      o("  verbosity  : " .. (cfg.verbosity or "auto") .. "   (what it says)", T.fg)
      o("  interface  : " .. (cfg.ui == "cli" and "cli" or "panels") .. "   (all seats)", T.fg)
      o("  repair     : " .. (cfg.repair and "RUN on next boot" or "off"), T.fg)
      o("  showConfig : " .. (cfg.showConfig and "on" or "off"), T.fg)
      o("  cpuTier    : " .. (cfg.cpuTier and ("Tier " .. cfg.cpuTier) or "auto"), T.fg)
      o("  dataTier   : " .. (cfg.dataTier and ("Tier " .. cfg.dataTier) or "auto"), T.fg)
      o("  ramGate    : " .. (cfg.ramGate == nil and "auto (measure)"
        or (cfg.ramGate and "plenty (force on)" or "tight (force off)")), T.fg)
      local anyAdv = false
      for _, f in ipairs(bootcfg.FEATURES) do
        local v = cfg.advanced and cfg.advanced[f]
        if v ~= nil then o("    +" .. f .. " : " .. (v and "on" or "off"), T.dim); anyAdv = true end
      end
      if not anyAdv then o("    (no advanced overrides)", T.dim) end
      o("Profiles: " .. table.concat(bootcfg.PROFILE_ORDER
        or { "minimal", "normal", "full", "diagnostic" }, " | "), T.dim)
      o("Verbosity: silent | splash | text | verbose | auto", T.dim)
      o("Set: bootsettings <profile|verbosity|ui|repair|show|cputier|datatier|ramgate|"
        .. table.concat(bootcfg.FEATURES, "/") .. "> <value>", T.dim)
      o("DEL during boot opens the full visual editor; S = Safe Mode once.", T.dim)
      local okS, sysinfo = pcall(require, "kernel.sysinfo")
      if okS and sysinfo then
        o("", T.dim)
        for _, r in ipairs(sysinfo.rows(sysinfo.gather(nil, { cpuTier = cfg.cpuTier, dataTier = cfg.dataTier }))) do
          if r.role == "section" then o(r.value .. ":", T.title)
          else o("  " .. (r.label ~= "" and (r.label .. ": ") or "") .. r.value, T.dim) end
        end
      end
      return
    end

    local val = (args[2] or ""):lower()
    local changed = false
    if sub == "profile" then
      if bootcfg.PROFILES[val] then cfg.profile = val; changed = true
      else o("profiles: " .. table.concat(bootcfg.PROFILE_ORDER
        or { "minimal", "normal", "full", "diagnostic" }, " "), T.error); return end
    elseif sub == "verbosity" then
      if val == "auto" then cfg.verbosity = nil; changed = true
      else
        local ok = false
        for _, vv in ipairs(bootcfg.VERBOSITY) do if vv == val then ok = true end end
        if ok then cfg.verbosity = val; changed = true
        else o("verbosity: silent splash text verbose (or auto)", T.error); return end
      end
    elseif sub == "show" or sub == "showconfig" then
      cfg.showConfig = (val == "on" or val == "true" or val == "1"); changed = true
    elseif sub == "cputier" or sub == "cpu" then
      if val == "auto" then cfg.cpuTier = nil; changed = true
      elseif val == "1" or val == "2" or val == "3" then cfg.cpuTier = tonumber(val); changed = true
      else o("cputier: auto | 1 | 2 | 3", T.error); return end
    elseif sub == "datatier" or sub == "data" then
      if val == "auto" then cfg.dataTier = nil; changed = true
      elseif val == "1" or val == "2" or val == "3" then cfg.dataTier = tonumber(val); changed = true
      else o("datatier: auto | 1 | 2 | 3", T.error); return end
    elseif sub == "ui" or sub == "interface" then
      if val == "panels" or val == "tui" then cfg.ui = nil; changed = true
      elseif val == "cli" then cfg.ui = "cli"; changed = true
      else o("ui: panels | cli", T.error); return end
    elseif sub == "repair" then
      if val == "on" or val == "once" or val == "1" then cfg.repair = true; changed = true
      elseif val == "off" or val == "0" then cfg.repair = false; changed = true
      else o("repair: on (runs once next boot, then clears) | off", T.error); return end
    elseif sub == "ramgate" or sub == "ram" then
      if val == "auto" then cfg.ramGate = nil; changed = true
      elseif val == "plenty" or val == "on" then cfg.ramGate = true; changed = true
      elseif val == "tight" or val == "off" then cfg.ramGate = false; changed = true
      else o("ramgate: auto (measure) | plenty (force extras on) | tight (force off)", T.error); return end
    elseif sub == "reset" then
      cfg = bootcfg._normalize({}); changed = true
    else
      local isFeat = false
      for _, f in ipairs(bootcfg.FEATURES) do if f == sub then isFeat = true end end
      if isFeat then
        cfg.advanced = cfg.advanced or {}
        if val == "auto" then cfg.advanced[sub] = nil
        elseif val == "on" then cfg.advanced[sub] = true
        elseif val == "off" then cfg.advanced[sub] = false
        else o(sub .. ": auto | on | off", T.error); return end
        changed = true
      else
        o("Unknown setting: " .. sub .. " (try: bootsettings show)", T.error); return
      end
    end
    if changed then
      local ok, err = bootcfg.save(fsMod, cfg)
      if ok then o("Saved. Applies on next boot (reboot to apply now).", T.highlight)
      else o("Save failed: " .. tostring(err), T.error) end
    end
  end

  -- Unified control for performance optimizations. swap is a BOOT feature
  -- (persists in boot.cfg, applies next boot); the display dirty-cell buffer
  -- is a RUNTIME setting (applies immediately). Read-only status is open to
  -- anyone; the toggles are admin-gated.
  C.optimize = function(args, o)
    local sub = (args[1] or ""):lower()
    local val = (args[2] or ""):lower()
    local okSc, screenMod = pcall(require, "kernel.screen")
    local function bootcfgIO()
      local okC, bootcfg = pcall(require, "kernel.bootcfg")
      local fsMod = _G._TOS and _G._TOS.fs
      if okC and bootcfg and fsMod then return bootcfg, fsMod end
    end

    if sub == "" or sub == "show" or sub == "status" then
      o("=== Optimizations ===", T.title)
      -- Disk swap: the boot-feature flag, plus whether it's live right now.
      local swapFlag = "auto (profile)"
      local bootcfg, fsMod = bootcfgIO()
      if bootcfg and fsMod then
        local cfg = bootcfg.load(fsMod)
        local v = cfg.advanced and cfg.advanced.swap
        if v ~= nil then swapFlag = v and "on" or "off" end
      end
      local sw = K.getSwap and K.getSwap()
      local swapLive = "inactive"
      if sw then
        local u = sw.usage()
        local pct = (u.max and u.max > 0) and math.floor(u.bytes * 100 / u.max) or 0
        swapLive = string.format("active %s/%s (%d%%)", fmtSz(u.bytes), fmtSz(u.max), pct)
      end
      o(string.format("  Disk swap      %-14s [%s]", swapFlag, swapLive),
        sw and T.fg or T.dim)
      o("    extends usable memory onto /var/swap (boot feature)", T.dim)
      -- Display buffer: runtime dirty-cell rendering optimization.
      local mode = (okSc and screenMod.bufferMode and screenMod.bufferMode()) or "?"
      o(string.format("  Display buffer %-14s", mode), T.fg)
      o("    skips GPU writes for unchanged cells (auto = memory-gated)", T.dim)
      -- Show the payoff so the optimization is visible, not just a toggle.
      if okSc and screenMod.bufferStats then
        local st = screenMod.bufferStats()
        if st.total > 0 then
          o(string.format("    this session: %d of %d cell-draws skipped (%d%%)",
            st.skipped, st.total, math.floor(st.ratio * 100 + 0.5)),
            st.ratio > 0 and T.highlight or T.dim)
        else
          o("    (no draws measured yet)", T.dim)
        end
      end
      o("", T.dim)
      o("optimize swap [status|keys|now|clear|on|off|auto]  boot toggle needs reboot", T.dim)
      o("optimize buffer <on|off|auto>   display; applies immediately", T.dim)
      return
    end

    if sub == "swap" then
      -- Runtime views first (folded in from the old `swap` command):
      -- status / keys read the live store, clear wipes it now.
      local sw = K.getSwap and K.getSwap()
      -- `now` forces a cold-buffer sweep. Paging is pressure-triggered, so on
      -- a roomy box it correctly never fires — which makes it impossible to
      -- confirm the wiring works. This makes it observable on demand.
      if val == "now" then
        local okT, tabsMod = pcall(require, "shell.panels.tabs")
        if not okT or not tabsMod.sweepCold then
          o("tab paging unavailable", T.error); return
        end
        if not sw then o("Swap not available", T.error); return end
        local n = tabsMod.sweepCold(S, true)
        local paged, lines = tabsMod.pagedStats(S)
        o(string.format("Paged out %d view tab(s) now.", n), T.highlight)
        o(string.format("%d tab(s) on disk, %d lines held there.", paged, lines), T.dim)
        o("They page back transparently the next time you open them.", T.dim)
        return
      end
      if val == "" or val == "status" or val == "keys" or val == "clear" then
        if not sw then o("Swap not available", T.error); return end
        if val == "clear" then
          if not adminOnly(o) then return end
          -- Restore anything paged FIRST: wiping the store under a tab that
          -- still points at it would turn its buffer into the "could not be
          -- restored" placeholder.
          local okT, tabsMod = pcall(require, "shell.panels.tabs")
          if okT and tabsMod.isPaged then
            for _, tb in ipairs(S.tabs or {}) do
              if tabsMod.isPaged(tb) then local _ = tb.content end
            end
          end
          sw.clear()
          o("Swap cleared.", T.highlight)
          return
        end
        local u = sw.usage()
        local pct = (u.max and u.max > 0) and math.floor(u.bytes * 100 / u.max) or 0
        o("=== Disk Swap (/var/swap) ===", T.title)
        o(string.format("Used:    %s / %s (%d%%)", fmtSz(u.bytes), fmtSz(u.max), pct),
          pct > 90 and T.warning or T.fg)
        o(string.format("Entries: %d", u.count), T.dim)
        if val == "keys" and sw.keys then
          local keys = sw.keys()
          if #keys == 0 then o("(no keys)", T.dim)
          else for _, k in ipairs(keys) do o("  " .. k, T.dim) end end
        end
        -- What is actually USING swap, and the knob that decides when.
        do
          local okT, tabsMod = pcall(require, "shell.panels.tabs")
          if okT and tabsMod.pagedStats then
            local paged, lines = tabsMod.pagedStats(S)
            o(string.format("View tabs paged: %d (%d lines)", paged, lines),
              paged > 0 and T.highlight or T.dim)
          end
          local pct, cfg = 25, (K.getConfig and K.getConfig())
          if cfg and cfg.get then pct = tonumber(cfg.get("swapPressurePct")) or 25 end
          o(string.format("Cold view buffers page out below %d%% free RAM"
            .. "  (swapPressurePct)", pct), T.dim)
        end
        o("Volatile: cleared on every boot. 'optimize swap clear' wipes now.", T.dim)
        o("'optimize swap now' pages cold tabs immediately (ignores pressure).", T.dim)
        return
      end
      -- Boot-feature toggle (the original optimize-swap path).
      if not adminOnly(o) then return end
      local bootcfg, fsMod = bootcfgIO()
      if not bootcfg then o("bootcfg/fs unavailable", T.error); return end
      local cfg = bootcfg.load(fsMod)
      cfg.advanced = cfg.advanced or {}
      if val == "auto" then cfg.advanced.swap = nil
      elseif val == "on" then cfg.advanced.swap = true
      elseif val == "off" then cfg.advanced.swap = false
      else o("optimize swap <status|keys|now|clear|on|off|auto>", T.error); return end
      local ok, err = bootcfg.save(fsMod, cfg)
      if ok then o("Disk swap set " .. val .. ". Applies on next boot.", T.highlight)
      else o("Save failed: " .. tostring(err), T.error) end
      return
    end

    if sub == "buffer" or sub == "display" then
      if not adminOnly(o) then return end
      if not (okSc and screenMod.setBuffer) then
        o("display buffer control unavailable", T.error); return
      end
      local ok, err = screenMod.setBuffer(val)
      if ok then o("Display buffer set " .. val .. " (applied now).", T.highlight)
      else o(tostring(err) or "invalid", T.error) end
      return
    end

    o("Usage: optimize [show | swap <on|off|auto> | buffer <on|off|auto>]", T.dim)
  end

  C.programs = function(args, o)
    local dirs = { "/bin", "/usr/bin", "/home/" .. S.who }
    o("Executables:", T.title)
    for _, dir in ipairs(dirs) do
      if F.isDirectory(dir) then
        local ok2, list = pcall(F.list, dir)
        if ok2 and list then
          local fitems = {}
          if type(list) == "table" then fitems = list
          elseif type(list) == "function" then for n in list do fitems[#fitems+1] = n end end
          local found = {}
          for _, n in ipairs(fitems) do
            if n:match("%.lua$") then found[#found+1] = n end
          end
          if #found > 0 then
            o(" " .. dir .. ":", T.dim)
            for _, n in ipairs(found) do o("   " .. n, T.file_lua or T.file_exec or T.highlight) end
          end
        end
      end
    end
  end
  C.log = function(args, o)
    if not adminOnly(o) then return end
    local logMod = K.getLog()
    if not logMod then o("Logger unavailable", T.error); return end

    -- Modes:
    --   log [N]        DEFAULT — open the on-disk /var/log/kernel.log in a
    --                  viewer (the full history across reboots). N limits to
    --                  the last N lines. Falls back to the in-memory ring if
    --                  the file isn't there yet, and to a freshly flushed
    --                  file if even the ring is empty.
    --   log ring [N]   Show the last N from the in-memory ring only (default
    --                  20) on the output row — quick peek, no viewer tab.
    --   log clear      Clear the in-memory ring (does NOT touch disk).
    --   log filter [<source> <debug|info|warn|error|off>]
    --                  List or set per-source level overrides, so one
    --                  subsystem can be cranked to DEBUG (or hushed)
    --                  without changing the global level.

    -- #REV — `log` with no args (or a bare count) now goes to the FILE, per
    -- the operator-facing contract "the log command should just go to the
    -- log file". `file`/`f`/`all` remain accepted aliases.
    local wantsFile = (args[1] == nil) or (args[1] == "file") or (args[1] == "f")
      or (args[1] == "all") or (tonumber(args[1]) ~= nil)
    if wantsFile then
      local logPath = "/var/log/kernel.log"
      -- The count can be args[1] (bare `log 50`) or args[2] (`log file 50`).
      local n = tonumber(args[1]) or tonumber(args[2])

      -- Make sure the freshest entries are on disk before we read it, so
      -- `log` reflects what just happened rather than the last flush tick.
      pcall(logMod.flush)

      if not F.exists(logPath) then
        -- File unavailable — fall back to the in-memory ring so the
        -- operator still sees something (and regenerates the file via the
        -- flush above on the next entry).
        o("No /var/log/kernel.log yet — showing in-memory ring.", T.dim)
        local entries = logMod.recent(n or 20)
        if #entries == 0 then o("(log is empty)", T.dim); return end
        local buf = { { " in-memory log ring (" .. #entries .. " entries)", T.title } }
        for _, e in ipairs(entries) do
          local color = T.fg
          if e.level >= 3 then color = T.error
          elseif e.level >= 2 then color = T.warning
          elseif e.level < 1 then color = T.dim end
          buf[#buf + 1] = { logMod.format(e), color }
        end
        openViewTab(buf, "log (ring)")
        return
      end

      local content = F.readFile(logPath)
      if not content then o("Cannot read " .. logPath, T.error); return end
      local lines = {}
      for line in content:gmatch("([^\n]*)\n?") do
        if line ~= "" then lines[#lines + 1] = line end
      end
      local first = (n and n > 0 and #lines - n + 1) or 1
      if first < 1 then first = 1 end
      -- Open in a viewer tab so the user can scroll. Cheaper than
      -- emitting all lines through `o` which spams S.lastOut.
      local buf = {}
      buf[#buf + 1] = { " /var/log/kernel.log  (" .. #lines .. " lines)", T.title }
      for i = first, #lines do
        local line = lines[i]
        local color = T.fg
        -- Best-effort level colouring from the log.format prefix.
        if line:find("%[FTL%]") or line:find("%[ERR%]") then color = T.error
        elseif line:find("%[WRN%]") then color = T.warning
        elseif line:find("%[DBG%]") then color = T.dim end
        buf[#buf + 1] = { line, color }
      end
      openViewTab(buf, "kernel.log")
      return
    end

    if args[1] == "filter" then
      -- Admin is already enforced at command entry; setSourceLevel
      -- re-checks the live session as belt-and-braces.
      local src, lvl = args[2], args[3]
      if not src then
        local names = { [0] = "DEBUG", "INFO", "WARN", "ERROR" }
        local n = 0
        for s, v in pairs(logMod.getSourceLevels()) do
          n = n + 1
          o(string.format("  %-12s %s+", s, names[v] or tostring(v)), T.fg)
        end
        if n == 0 then o("(no per-source filters; global level applies)", T.dim) end
        o("Usage: log filter <source> <debug|info|warn|error|off>", T.dim)
        return
      end
      if lvl == "off" or lvl == "clear" then
        logMod.setSourceLevel(src, nil)
        o("Filter cleared for '" .. src .. "'.", T.fg)
      elseif lvl then
        local ok2, ferr = logMod.setSourceLevel(src, lvl)
        if ok2 then o("Source '" .. src .. "' now logs at " .. lvl:upper() .. "+.", T.fg)
        else o(ferr or "Filter update failed", T.error) end
      else
        o("Usage: log filter <source> <debug|info|warn|error|off>", T.dim)
      end
      return
    end

    if args[1] == "clear" then
      -- Force-flush before clearing so anything still in the ring
      -- lands on disk (the on-disk log is the long-term record).
      pcall(logMod.flush)
      -- We don't expose a clear() on log.lua's ring — easiest is to
      -- emit a marker entry so a subsequent `log` shows a clean
      -- separator. The ring will fill normally from there.
      logMod.info("log", "--- ring cleared on operator request ---")
      o("Ring marker recorded; old entries still on disk.", T.dim)
      return
    end

    if args[1] == "ring" or args[1] == "r" or args[1] == "tail" then
      local count = tonumber(args[2]) or 20
      local entries = logMod.recent(count)
      if #entries == 0 then o("(no log entries in ring)", T.dim); return end
      for _, e in ipairs(entries) do
        local color = T.dim
        if e.level >= 3 then color = T.error
        elseif e.level >= 2 then color = T.warning
        elseif e.level >= 1 then color = T.fg end
        o(logMod.format(e), color)
      end
      o(#entries .. " ring entries (use 'log' for full on-disk history)", T.dim)
      return
    end

    o("Usage: log [N] | log ring [N] | log clear | log filter ...", T.dim)
    o("  log        Open the full on-disk log (last N lines if given)", T.dim)
    o("  log ring   Quick peek at the in-memory ring", T.dim)
  end
  C.bg = function(args, o)
    -- #SEC C7 — explicit tier gate. The CATEGORY map in commands.lua only
    -- controlled lazy loading, not dispatch, so a GUEST shell could spawn
    -- arbitrary background Lua via this dispatcher. Re-check here at the
    -- function entry where it actually fires.
    if not adminOnly(o) then return end
    if not args[1] then
      o("Usage: bg <script.lua> [args...]", T.dim)
      o("  Runs a Lua script in a background tab.", T.dim)
      return
    end
    local path = rp(args[1])
    local data = F.readFile(path)
    if not data then o("Cannot read: " .. args[1], T.error); return end
    local fn2, err2 = load(data, "=" .. args[1], "t", makeProgramEnv{name=args[1]})
    if not fn2 then o("Compile error: " .. tostring(err2), T.error); return end
    local runArgs = {}
    for i = 2, #args do runArgs[#runArgs+1] = args[i] end
    local name = args[1]:match("[^/]+$") or args[1]
    -- Create an output tab for this background task
    local bgTab = deps.createTab("output", "bg:" .. name, {
      content = { "Background task: " .. name, "PID: (starting...)", "" },
      offset = 0,
      pid = nil,
    })
    local tabIdx = #deps.tabs
    -- Capture output into the tab's content
    local BG_MAX_LINES = 500
    local function bgPrint(...)
      local parts = {}
      for i2 = 1, select("#", ...) do parts[#parts+1] = tostring(select(i2, ...)) end
      local line = table.concat(parts, "\t")
      bgTab.content[#bgTab.content + 1] = line
      -- Trim oldest lines if over limit (keep recent output)
      if #bgTab.content > BG_MAX_LINES then
        local trim = #bgTab.content - BG_MAX_LINES
        for i2 = 1, BG_MAX_LINES do
          bgTab.content[i2] = bgTab.content[i2 + trim]
        end
        for i2 = BG_MAX_LINES + 1, #bgTab.content do
          bgTab.content[i2] = nil
        end
        bgTab.offset = math.max(0, bgTab.offset - trim)
      end
      -- Auto-scroll if user is at the end
      local viewH2 = H - 3
      if bgTab.offset >= #bgTab.content - viewH2 - 2 then
        bgTab.offset = math.max(0, #bgTab.content - viewH2)
      end
    end
    local pid = P.spawn("bg:" .. name, function()
      -- Build sandboxed env with custom print for background output
      local taskEnv = makeProgramEnv{ name = args[1], stdout = bgPrint }
      local taskFn = load(data, "=" .. args[1], "t", taskEnv)
      if taskFn then
        local tok, terr = pcall(taskFn, table.unpack(runArgs))
        if not tok then
          bgPrint("Error: " .. tostring(terr))
        end
      end
      bgPrint("", "--- Task finished ---")
    end, {
      priority = 8,
      source   = "user",
      tsr      = true,
    })
    bgTab.pid = pid
    bgTab.content[2] = "PID: " .. pid
    o("Started background task: " .. name .. " (PID " .. pid .. ")", T.highlight)
    local okH, home = pcall(require, "shell.panels.home")
    local cyc = (okH and home) and home.cycleKeyLabel(S) or "F2"
    o("Switch to its tab with " .. cyc .. ", or use 'kill " .. pid .. "' to stop.", T.dim)
  end

  C.run = function(args, o)
    -- #SEC C7 — explicit tier gate (see C.bg).
    if not adminOnly(o) then return end
    if not args[1] then o("Usage: run <file.lua>", T.dim); return end
    local path = rp(args[1])
    local data = F.readFile(path)
    if not data then o("Cannot read: " .. args[1], T.error); return end
    local fn2, err2 = load(data, "=" .. args[1], "t", makeProgramEnv{name=args[1], stdout=function(line) o(line, T.fg) end})
    if not fn2 then o("Compile error: " .. tostring(err2), T.error); return end
    local runArgs = {}
    for i = 2, #args do runArgs[#runArgs+1] = args[i] end
    local ok2, result = pcall(fn2, table.unpack(runArgs))
    if not ok2 then o("Runtime error: " .. tostring(result), T.error)
    elseif result ~= nil then o(tostring(result), T.fg) end
  end

  C.lua = function(args, o)
    -- REPL has full _ENV access (debugging tool) — restrict to ROOT.
    -- #SEC M-7 — gate on the LIVE seat tier (rootOnly resolves the seat
    -- token's current session), not the cached S.userTier snapshot taken at
    -- panel construction. The cached value goes stale when a session is
    -- demoted/expires mid-session, which would otherwise leave a root REPL
    -- reachable after the principal lost root.
    if not rootOnly(o) then return end
    -- #SEC M21 — audit every REPL session entry. The REPL grants
    -- arbitrary code execution at root tier; operators need a log
    -- entry per session even when the operator IS root (post-hoc
    -- forensics, "who ran ad-hoc code yesterday at 23:14?").
    pcall(function()
      local logMod = require("kernel.log")
      if logMod and logMod.info then
        logMod.info("repl", "REPL session opened by " .. tostring(S.who or "?"))
      end
    end)
    local replOpenedAt = computer.uptime()
    D.fill(1, 1, W, H, " ", T.fg, T.bg)
    D.fill(1, 1, W, 1, " ", T.bar_fg, T.bar_bg)
    D.set(1, 1, " Lua REPL  type 'exit' to quit", T.bar_fg, T.bar_bg)
    D.set(1, 1, " Lua REPL  'exit' to quit | blank line runs/cancels a block",
      T.bar_fg, T.bar_bg)
    local row   = 2
    local hist  = {}
    local function reout(text, color)
      if row > H - 1 then
        local gpu2 = D.getGpu()
        if gpu2 and gpu2.copy then gpu2.copy(1, 3, W, H-3, 0, -1) end
        D.fill(1, H-1, W, 1, " ", T.fg, T.bg)
        row = H - 1
      end
      D.set(1, row, tostring(text):sub(1,W), color or T.fg, T.bg)
      row = row + 1
    end
    -- #REV (#13) — multi-line REPL. Lines accumulate into `chunkLines`; the
    -- buffer is run only once it compiles. An "unexpected <eof>" compile
    -- error means the statement is unfinished (open function/if/table/…), so
    -- we keep reading with a ">>" continuation prompt instead of erroring.
    -- A blank line force-runs (or cancels) the pending block.
    local function isIncomplete(err)
      return type(err) == "string" and err:find("<eof>", 1, true) ~= nil
    end
    local chunkLines = {}
    while true do
      if row > H - 1 then
        D.getGpu().copy(1, 3, W, H-3, 0, -1)
        D.fill(1, H-1, W, 1, " ", T.fg, T.bg)
        row = H - 1
      end
      local cont = #chunkLines > 0
      local prompt = cont and ">> " or "> "
      D.fill(1, row, W, 1, " ", T.fg, T.bg)
      D.set(1, row, prompt, T.highlight, T.bg)
      local buf  = ""
      local hidx2 = #hist + 1
      local px = #prompt + 1
      while true do
        D.fill(px, row, W - px + 1, 1, " ", T.fg, T.bg)
        D.set(px, row, buf .. "_", T.fg, T.bg)
        local sig, _, ch2, co2 = deps.pullSignal()
        if sig == "key_down" then
          if co2 == 28 then break
          elseif co2 == 14 then if #buf > 0 then buf = buf:sub(1,-2) end
          elseif co2 == 200 then if hidx2 > 1 then hidx2 = hidx2 - 1 buf = hist[hidx2] or "" end
          elseif co2 == 208 then
            if hidx2 < #hist then hidx2 = hidx2 + 1 buf = hist[hidx2] or ""
            else hidx2 = #hist + 1 buf = "" end
          elseif ch2 and ch2 >= 32 and ch2 < 127 then buf = buf .. string.char(ch2) end
        elseif sig == "clipboard" and type(ch2) == "string" then
          -- A pasted multi-line block: split on newlines and queue each.
          buf = buf .. ch2:gsub("\r", "")
          local nl = buf:find("\n", 1, true)
          if nl then
            -- keep only the first line here; the rest replay as input below
            -- (simpler: collapse newlines to spaces so it still compiles)
            buf = buf:gsub("\n", " ")
          end
        end
      end
      row = row + 1

      -- Exit only when not mid-block.
      if (buf == "exit" or buf == "quit") and not cont then break end

      if buf == "" and not cont then
        -- blank line at top level: nothing to do
      elseif buf == "" and cont then
        -- blank line cancels the pending block
        chunkLines = {}
        reout("(cancelled)", T.dim)
      else
        chunkLines[#chunkLines + 1] = buf
        local src = table.concat(chunkLines, "\n")
        -- Try as an expression first (so `1+1` prints 2), then as a chunk.
        local fnTry, errExpr = load("return " .. src, "=repl", "t")
        if not fnTry then fnTry, errExpr = load(src, "=repl", "t") end
        if not fnTry and isIncomplete(errExpr) then
          -- Unfinished — keep reading more lines (>> prompt next iteration).
          goto repl_continue
        end
        -- Complete (compiled) or a real syntax error: this block is done.
        chunkLines = {}
        hist[#hist+1] = src
        -- #SEC M21 — log each executed REPL chunk so a compromised root
        -- account leaves a trail (first 120 chars; kernel log sanitizes).
        pcall(function()
          local logMod = require("kernel.log")
          if logMod and logMod.info then
            logMod.info("repl", "[" .. tostring(S.who or "?") .. "] " ..
              src:gsub("\n", " ; "):sub(1, 120))
          end
        end)
        local replEnv = makeProgramEnv{
          name = "repl",
          caps = {
            ["fs.read"]=true, ["fs.write"]=true, ["compat.io"]=true,
            ["component"]=true, ["load"]=true, ["net"]=true,
            -- #SEC M21 — REPL is a debug tool; not all sessions need
            -- peripheral.modem/redstone/etc. Grant the gated caps too
            -- since this is root-tier already, but the audit log above
            -- means each grant is attributable.
            ["peripheral.modem"]=true, ["peripheral.redstone"]=true,
            ["peripheral.robot"]=true, ["peripheral.inventory"]=true,
            ["peripheral.tape"]=true,
          },
          stdout = function(line) reout(line, T.fg) end,
        }
        -- Compile against the sandbox env (the earlier compile used no env
        -- purely to detect incompleteness). Expression form first so the
        -- value prints; then statement form.
        local fn3, err3 = load("return " .. src, "=repl", "t", replEnv)
        if not fn3 then fn3, err3 = load(src, "=repl", "t", replEnv) end
        if fn3 then
          local ok3, res = pcall(fn3)
          if ok3 then
            if res ~= nil then reout(tostring(res), T.highlight) end
          else reout(tostring(res), T.error) end
        else reout("Error: " .. tostring(err3), T.error) end
      end
      ::repl_continue::
    end
    -- #SEC M21 — log session close so the audit trail has matched pairs.
    pcall(function()
      local logMod = require("kernel.log")
      if logMod and logMod.info then
        logMod.info("repl", string.format("REPL session closed by %s (%.1fs, %d cmds)",
          tostring(S.who or "?"), computer.uptime() - replOpenedAt, #hist))
      end
    end)
  end

  C.edit = function(args, o)
    -- #SEC C7 — admin-only. The editor honours canWrite on save, but
    -- guarding entry too means a GUEST shell can't even read protected
    -- files through the editor's lower-friction interface.
    if not adminOnly(o) then return end
    if not args[1] then o("Usage: edit <file>", T.dim); return end
    local path = rp(args[1])
    openEditTab(path)
  end
  -- ── protect ──────────────────────────────────────────────────────
  --! The protected-path set is defence-in-depth against a TAMPERED admin
  --! session. It was also an absolute wall for the machine's owner:
  --! creating a file in /etc, clearing OpenOS's man pages out of
  --! /usr/man, and tidying an install were simply refused, with no
  --! supported way to say "yes, I mean it" — the code's own advice was
  --! to go around securefs with raw kernel.fs, which gives up both the
  --! safety and the audit trail.
  --!
  --! Root can now stand it down for THEIR OWN SESSION. Admin cannot, so
  --! the defence still does its job. It dies with the session.
  C.protect = function(args, o)
    if not rootOnly(o) then return end
    local okS, sfs = pcall(require, "kernel.securefs")
    if not okS or not sfs or not sfs.setOperatorOverride then
      o("This build has no protected-path override.", T.error); return
    end
    local sess = S and S.session
    local state = sfs.operatorOverride and sfs.operatorOverride(sess)
    local verb = (args[1] or ""):lower()

    if verb == "" or verb == "status" then
      o("Protected-path guards are " ..
        (state and "STOOD DOWN for this session." or "active."),
        state and T.warning or T.highlight)
      o("", T.dim)
      o("They stop even root from writing under /tos, /etc, /usr and", T.dim)
      o("/var through securefs — a line against a tampered admin", T.dim)
      o("session, not an ACL. You own this machine, so you can stand", T.dim)
      o("them down; nobody below root can, and it ends with this", T.dim)
      o("session.", T.dim)
      o("", T.dim)
      o("  protect off    stand the guards down for this session", T.dim)
      o("  protect on     put them back", T.dim)
      return
    end

    if verb == "off" then
      if state then o("Already stood down for this session.", T.dim); return end
      local ok2, err = sfs.setOperatorOverride(sess, true)
      if not ok2 then o("Refused: " .. tostring(err), T.error); return end
      o("Protected-path guards STOOD DOWN for this session.", T.warning)
      o("You can now write and remove under /tos, /etc, /usr and /var.", T.dim)
      o("Every path allowed this way is written to the kernel log.", T.dim)
      o("Deleting the wrong thing here is how a machine stops booting —", T.dim)
      o("`protect on` when you are done.", T.dim)
    elseif verb == "on" then
      if not state then o("Guards are already active.", T.dim); return end
      local ok2, err = sfs.setOperatorOverride(sess, false)
      if not ok2 then o("Refused: " .. tostring(err), T.error); return end
      o("Protected-path guards active again.", T.highlight)
    else
      o("Usage: protect [status|off|on]", T.dim)
    end
  end

  -- ── reclaim ──────────────────────────────────────────────────────
  --! Installing TOS over OpenOS leaves OpenOS behind: /bin, /boot and
  --! /lib are untouched by the TOS installer (measured — TOS installs
  --! 152 files and NONE of them land there), and after the compat-shim
  --! fix nothing in the TOS runtime resolves into them either. On the
  --! 4 MB drive this was found on, that is most of a megabyte of dead
  --! weight, and /bin being on PATH means a command TOS does not
  --! implement silently runs OpenOS's copy instead — which is how `tree`
  --! came to fail with a sandbox error rather than "not a command".
  --!
  --! Dry run by default. Nothing is removed without --apply, and it
  --! refuses outright unless /init.lua is TOS's, so it cannot fire on a
  --! machine where OpenOS is still the operating system.
  C.reclaim = function(args, o)
    if not rootOnly(o) then return end

    local apply = false
    for _, a in ipairs(args or {}) do
      if a == "--apply" then apply = true end
    end

    local okF, kfs = pcall(require, "kernel.fs")
    if not okF or not kfs then o("Filesystem unavailable.", T.error); return end

    --! The safety interlock. If /init.lua is not TOS's, this machine
    --! boots OpenOS and its files are not leftovers -- they are the
    --! operating system. Checked by content, not by asking politely.
    local initSrc = kfs.readFile("/init.lua")
    if not initSrc then
      o("Cannot read /init.lua — refusing to guess what this machine boots.", T.error)
      return
    end
    if not (initSrc:find("_TOS", 1, true) or initSrc:find("TOS Kernel", 1, true)
            or initSrc:find("tos/kernel", 1, true)) then
      o("/init.lua is not TOS's — this machine boots OpenOS.", T.error)
      o("Those files are the operating system here, not leftovers.", T.dim)
      o("Refusing.", T.dim)
      return
    end

    -- OpenOS-owned trees. TOS installs nothing into any of them; that is
    -- checked by test_reclaim.lua against the real manifest, so this list
    -- cannot quietly start overlapping with ours.
    --! Identical to install.lua's OPENOS_ONLY_TREES on purpose --
    --! test_reclaim.lua fails if they diverge. Nothing under /home is
    --! touched: .shrc is OpenOS's, but it sits in user data and a
    --! cleanup that reaches into /home is a different promise than the
    --! one this makes.
    local TREES = { "/bin", "/boot", "/lib" }
    local EXTRA = {}

    local function walk(path, acc)
      if not kfs.exists(path) then return end
      if kfs.isDirectory(path) then
        for _, name in ipairs(kfs.list(path) or {}) do
          walk(path .. "/" .. (name:gsub("/$", "")), acc)
        end
        acc.dirs[#acc.dirs + 1] = path
      else
        acc.files[#acc.files + 1] = path
        acc.bytes = acc.bytes + (kfs.size(path) or 0)
      end
    end

    local acc = { files = {}, dirs = {}, bytes = 0 }
    for _, t in ipairs(TREES) do walk(t, acc) end
    for _, f in ipairs(EXTRA) do
      if kfs.exists(f) and not kfs.isDirectory(f) then
        acc.files[#acc.files + 1] = f
        acc.bytes = acc.bytes + (kfs.size(f) or 0)
      end
    end

    if #acc.files == 0 and #acc.dirs == 0 then
      o("Nothing to reclaim — no OpenOS leftovers found.", T.highlight)
      return
    end

    local kb = math.floor(acc.bytes / 1024 + 0.5)
    o(string.format("OpenOS leftovers: %d file(s) in %d director(ies), ~%d KB",
      #acc.files, #acc.dirs, kb), T.title)
    for _, t in ipairs(TREES) do
      if kfs.exists(t) then o("  " .. t, T.fg) end
    end
    for _, f in ipairs(EXTRA) do if kfs.exists(f) then o("  " .. f, T.fg) end end
    o("", T.dim)
    o("TOS installs no files into these; nothing in the TOS runtime", T.dim)
    o("loads from them. An OpenOS floppy remains your recovery path —", T.dim)
    o("this install stopped being one when TOS replaced /init.lua.", T.dim)
    o("", T.dim)
    o("Removing /bin also changes what an unknown command does: today", T.dim)
    o("it may run OpenOS's version, afterwards you get 'not a command'.", T.dim)

    if not apply then
      o("", T.dim)
      o("Dry run. Nothing was removed.", T.highlight)
      o("Run it for real with:  reclaim --apply", T.dim)
      return
    end

    o("", T.dim)
    o("Removing...", T.warning)
    local removed, failedN, freed = 0, 0, 0
    for _, f in ipairs(acc.files) do
      local sz = kfs.size(f) or 0
      if kfs.remove(f) then removed = removed + 1; freed = freed + sz
      else failedN = failedN + 1 end
    end
    -- Directories last, deepest first (walk appends parents after children).
    for _, d in ipairs(acc.dirs) do pcall(kfs.remove, d) end

    o(string.format("Removed %d file(s), ~%d KB reclaimed.",
      removed, math.floor(freed / 1024 + 0.5)), T.highlight)
    if failedN > 0 then
      o(failedN .. " file(s) could not be removed.", T.warning)
    end
    o("Reboot when convenient; nothing running depends on them.", T.dim)
  end

  C.flash = function(args, o)
    if not rootOnly(o) then return end
    if not args[1] then
      o("Usage: flash <bios.lua>", T.dim)
      o("Flashes the given file to the system EEPROM.", T.dim)
      return
    end
    local path = rp(args[1])
    local eepromAddr = nil
    for addr in component.list("eeprom") do eepromAddr = addr; break end
    if not eepromAddr then
      o("No EEPROM detected. Insert EEPROM, or press Ctrl+C to abort...", T.warning)
      -- Wait up to 60s for hot-plug. Accept component_added for eeprom OR
      -- any key_down with Ctrl held (cooperative cancel) so the shell isn't
      -- pinned indefinitely if the operator changes their mind.
      local deadline = computer.uptime() + 60
      while not eepromAddr and computer.uptime() < deadline do
        local sig, addr, compType = deps.pullSignal(1)
        if sig == "component_added" and compType == "eeprom" then
          eepromAddr = addr
        elseif sig == "interrupted" then
          o("Aborted.", T.dim); return
        end
      end
      if not eepromAddr then
        o("Timed out waiting for EEPROM.", T.error); return
      end
      o("EEPROM detected.", T.highlight)
    end
    local eeprom = component.proxy(eepromAddr)
    local data, err = F.readFile(path)
    if not data then o("Cannot read: " .. tostring(err), T.error); return end
    local maxSize = eeprom.getSize()
    if #data > maxSize then
      o(string.format("File too large: %d bytes (EEPROM max: %d)", #data, maxSize), T.error)
      return
    end

    -- #107 — verify the payload before we let the user brick an EEPROM.
    -- Parse as Lua text (reject bytecode), then look for a marker that
    -- this is actually a BIOS. The heuristic is intentionally loose:
    -- any sensible BIOS either calls getBootAddress or probes for a
    -- filesystem component to chain-load /init.lua. A generic script
    -- will fail both checks.
    -- Empty env: the chunk is only syntax-checked, never run — but if a
    -- future edit ever did call it, it would execute against nothing.
    local chk, cerr = load(data, "=flash-verify", "t", {})
    if not chk then
      o("Refusing to flash: file does not parse as Lua text.", T.error)
      o("  " .. tostring(cerr), T.dim)
      return
    end
    local looksLikeBios =
      data:find("getBootAddress", 1, true) or
      data:find("setBootAddress", 1, true) or
      (data:find("component.list", 1, true) and data:find("init.lua", 1, true))
    if not looksLikeBios then
      -- Soft warning — let the operator override if they really mean it,
      -- but they have to type 'force' rather than y/N.
      -- #REV — the prompt MESSAGE must be passed into promptInput: it
      -- clears OUT_ROW and draws its own msg, so a separate drawOutRow()
      -- here was instantly wiped, leaving a blank prompt the operator
      -- couldn't answer (and any key but the exact word aborted).
      local forced = (promptInput and
        promptInput("Doesn't look like a BIOS — type 'force' to flash anyway: ", 16)) or ""
      if forced ~= "force" then
        o("Aborted (safety check).", T.dim)
        return
      end
    end

    local elabel = eeprom.getLabel and eeprom.getLabel() or "(no label)"
    -- #102 — surface the source path AND the current boot-drive address
    -- so the operator knows exactly what's about to happen before
    -- committing to an irreversible write.
    local curBoot = "(unknown)"
    do
      local okB, b = pcall(computer.getBootAddress)
      if okB and b then curBoot = b:sub(1, 8) .. "..." end
    end
    -- #SEC H-13 / H29 — show a fingerprint of the BIOS payload so the
    -- operator can compare against a known-good value before the write
    -- commits. We ONLY ever display a real SHA-256 here — there is no
    -- weak (FNV/truncated) fallback. Per CLAUDE.md the weak-fingerprint
    -- pattern must not recur: a 64-bit prefix is cheap to second-preimage,
    -- so we print the FULL 64-hex digest for a meaningful comparison. If
    -- the crypto module is unreachable we say so explicitly rather than
    -- printing a bland line the operator might read as "verified".
    local fingerprint = nil
    do
      local okC, cryptoMod = pcall(require, "kernel.crypto")
      if okC and cryptoMod and cryptoMod.hash then
        local okH, h = pcall(cryptoMod.hash, data)
        if okH and type(h) == "string" and #h == 64 then fingerprint = h end
      end
    end
    o(string.format("  Source : %s (%d bytes)", path, #data), T.dim)
    if fingerprint then
      o(string.format("  SHA-256: %s", fingerprint), T.dim)
    else
      o("  SHA-256: UNAVAILABLE - integrity cannot be verified", T.warning)
    end
    o(string.format("  EEPROM : %s", elabel), T.dim)
    o(string.format("  Boot   : %s", curBoot), T.dim)
    -- #SEC H29 — require the operator to TYPE the literal "flash"
    -- rather than a single y/N keystroke. Bumping into 'y' while the
    -- prompt is on screen used to be enough to brick the machine.
    -- #REV — pass the instruction INTO promptInput (it owns OUT_ROW and
    -- clears it), or the operator just sees an empty prompt and every
    -- keystroke "aborts" because it isn't the word "flash".
    local typed = (promptInput and promptInput('Type "flash" to confirm: ', 16)) or ""
    local confirmed = (typed == "flash")
    if confirmed then
      -- eeprom.set can fail (hardware error, write-protect, removed mid-flash).
      -- Capture the return so we don't claim success on a silent failure.
      local setOk, setErr = pcall(eeprom.set, data)
      if not setOk then
        o("Flash failed: " .. tostring(setErr), T.error)
      else
        o("EEPROM flashed! " .. #data .. " bytes written.", T.highlight)
        o("Reboot for changes to take effect.", T.dim)
      end
    else
      o("Aborted.", T.dim)
    end
  end
  C.users = function(args, o)
    if not adminOnly(o) then return end
    if not U then o("No user system", T.error); return end
    o(string.format(" %-12s %-8s %s", "User", "Tier", "Status"), T.title)
    o(string.rep("-", 34), T.border)
    local list = U.list and U.list() or U.listUsers and U.listUsers() or {}
    for _, u in ipairs(list) do
      local ustat = u.locked and "LOCKED" or "OK"
      o(string.format(" %-12s %-8s %s",
        u.username or u.user or "?",
        tostring(u.tier or u.accessLevel or "?"),
        ustat),
        u.locked and T.error or T.dim)
    end
  end
  -- Resolve the ACTOR (invoking user) for user-management operations.
  -- Previously these commands hard-coded "root" as the actor, which
  -- meant every privilege check inside users.lua granted unconditional
  -- success regardless of who typed the command. Root-gating at the
  -- shell level (rootOnly) catches most of it, but the users.lua audit
  -- log and any tier-based fine-grained checks got "root" for every
  -- entry. We now pass the actual caller so audit is correct and any
  -- later ACL tightening in users.lua sees the real principal.
  local function currentActor()
    if not U then return "root" end
    local s = U.getSession(st)
    return (s and s.user) or "root"
  end

  C.useradd = function(args, o)
    if not rootOnly(o) then return end
    if not U then o("No user system", T.error); return end
    local name = args[1]
    if not name then o("Usage: useradd <username>", T.dim); return end
    local pass = promptInput("Password for " .. name .. ": ", 64, true)
    if not pass or pass == "" then o("Aborted.", T.dim); return end
    local pass2 = promptInput("Confirm password: ", 64, true)
    if pass2 ~= pass then o("Passwords do not match.", T.error); return end
    local ok2, err2 = U.create(currentActor(), name, pass, 1)
    if ok2 then S.lastOut = { "User '" .. name .. "' created.", T.highlight }
    else      S.lastOut = { tostring(err2), T.error } end
  end

  C.userdel = function(args, o)
    if not rootOnly(o) then return end
    if not U then o("No user system", T.error); return end
    local name = args[1]
    if not name then o("Usage: userdel <username>", T.dim); return end
    local confirm = promptInput("Delete '" .. name .. "'? [y/N]: ", 1, false)
    if confirm ~= "y" and confirm ~= "Y" then o("Aborted.", T.dim); return end
    local ok2, err2 = U.delete(currentActor(), name)
    if ok2 then S.lastOut = { "User '" .. name .. "' deleted.", T.highlight }
    else      S.lastOut = { tostring(err2), T.error } end
  end

  C.usermod = function(args, o)
    if not rootOnly(o) then return end
    if not U then o("No user system", T.error); return end
    local name, action = args[1], args[2]
    if not name or not action then
      o("Usage: usermod <username> lock|unlock|admin|user|root", T.dim); return
    end
    local actor = currentActor()
    local ok2, err2
    if action == "lock" then
      if U.setLocked then ok2, err2 = U.setLocked(actor, name, true)
      else ok2, err2 = false, "setLocked unavailable" end
      if ok2 then S.lastOut = { "'" .. name .. "' locked.", T.highlight }
      else      S.lastOut = { tostring(err2), T.error } end
    elseif action == "unlock" then
      if U.setLocked then ok2, err2 = U.setLocked(actor, name, false)
      else ok2, err2 = false, "setLocked unavailable" end
      if ok2 then S.lastOut = { "'" .. name .. "' unlocked.", T.highlight }
      else      S.lastOut = { tostring(err2), T.error } end
    elseif action == "admin" then
      -- The computer wants ROOT, not admin. Deadpan nudge (the real egg is
      -- on `usermod computer root`).
      if name:lower() == "computer" then
        o("Failure. Did you mean 'usermod computer root'?", T.error); return
      end
      if U.setTier then ok2, err2 = U.setTier(actor, name, 2)
      else ok2, err2 = false, "setTier unavailable" end
      if ok2 then S.lastOut = { "'" .. name .. "' promoted to admin.", T.highlight }
      else      S.lastOut = { tostring(err2), T.error } end
    elseif action == "root" then
      -- ── Easter egg: handing ROOT to an account named "computer" ──
      -- Reachable by root, or by anyone who elevates first (sudo usermod
      -- computer root) since usermod is root-gated. Fires once per session;
      -- the grant is intercepted as pure THEATRE (nothing granted, no files
      -- touched), then the account keeps its normal tier. Fully guarded so
      -- it never blocks real account management.
      if name:lower() == "computer" and S.D
         and not (_G._TOS and _G._TOS._takeoverFired) then
        _G._TOS = _G._TOS or {}
        _G._TOS._takeoverFired = true   -- disabled for the rest of the session
        local okT, takeover = pcall(require, "shell.panels.takeover")
        if okT and takeover and takeover.run then
          local okRun, ending = pcall(takeover.run, S)
          if S.D.invalidate then pcall(S.D.invalidate) end   -- full repaint
          pcall(function()
            _G._TOS.logObj.info("kernel",
              "The computer briefly reconsidered its priorities (" ..
              tostring(okRun and ending or "?") .. ")")
          end)
          S.lastOut = { "Access control updated.", T.dim }   -- deadpan
          return
        end
      end
      -- Non-"computer" account, or egg already fired this session: real grant
      -- (setTier enforces "only root-effective callers may grant root").
      if U.setTier then ok2, err2 = U.setTier(actor, name, 3)
      else ok2, err2 = false, "setTier unavailable" end
      if ok2 then S.lastOut = { "'" .. name .. "' promoted to root.", T.highlight }
      else      S.lastOut = { tostring(err2), T.error } end
    elseif action == "user" then
      if U.setTier then ok2, err2 = U.setTier(actor, name, 1)
      else ok2, err2 = false, "setTier unavailable" end
      if ok2 then S.lastOut = { "'" .. name .. "' set to user.", T.highlight }
      else      S.lastOut = { tostring(err2), T.error } end
    else
      o("Unknown action: " .. action, T.error)
      o("Valid: lock, unlock, admin, user", T.dim)
    end
  end
  C.lsdev = function(args, o)
    o(string.format(" %-16s %-10s %s", "Type", "Address", "Info"), T.title)
    o(string.rep("-", 46), T.dim)
    local count = 0
    for addr, ctype in component.list() do
      local cinfo = ""
      if ctype == "filesystem" then
        local ok2, px = pcall(component.proxy, addr)
        if ok2 and px then
          local lbl = px.getLabel and px.getLabel() or ""
          local kb  = px.spaceTotal and math.floor(px.spaceTotal()/1024) or 0
          cinfo = (lbl ~= "" and '"'..lbl..'" ' or "") .. kb .. "K"
        end
      elseif ctype == "modem" then
        local ok2, px = pcall(component.proxy, addr)
        if ok2 and px and px.isWireless then
          cinfo = px.isWireless() and "wireless" or "wired"
        end
      elseif ctype == "drive" then
        -- Unmanaged raw drive (no filesystem until formatted; see 'drive').
        local ok2, px = pcall(component.proxy, addr)
        if ok2 and px and px.getCapacity then
          cinfo = "raw " .. math.floor((px.getCapacity() or 0) / 1024) .. "K"
        end
      elseif ctype == "openprinter" then
        -- OpenPrinter: the consumables ARE the interesting state. A printer
        -- with no paper is present, addressed and useless, and that reads
        -- identically to a working one unless we say so here. Every level
        -- call is pcall'd individually — the mod throws rather than
        -- returning nil, and the 1.7 branch is missing some of the newer
        -- getters, so one absent method must not blank the whole row.
        local ok2, px = pcall(component.proxy, addr)
        if ok2 and px then
          local function lvl(fn)
            if type(fn) ~= "function" then return "?" end
            local okL, v = pcall(fn)
            return (okL and tonumber(v)) and tostring(math.floor(v)) or "?"
          end
          cinfo = "paper " .. lvl(px.getPaperLevel)
               .. " ink " .. lvl(px.getBlackInkLevel)
               .. "/" .. lvl(px.getColorInkLevel)
        end
      end
      o(string.format(" %-16s %s  %s", ctype, addr:sub(1,8).."...", cinfo), T.fg)
      count = count + 1
    end
    if count == 0 then o("  (no peripherals detected)", T.dim) end
  end
  C.devices = C.lsdev   -- operator-friendly alias (v1.4.0)

  C.mount = function(args, o)
    if args[1] and args[2] then
      if not adminOnly(o) then return end
      local target, mntArg = args[1], args[2]
      -- #SEC M20 — when matching by label, collect ALL candidates and
      -- pick deterministically (address-sorted) rather than relying on
      -- component.list iteration order, which OC does not guarantee
      -- across reboots. Two disks with the same label otherwise mount
      -- in flip-flopping order — bookmark paths break.
      local candidates  = {}   -- label matches
      local addrMatches = {}   -- address-prefix matches
      for addr in component.list("filesystem") do
        if addr:sub(1, #target) == target then
          addrMatches[#addrMatches + 1] = addr
        else
          local ok2, px = pcall(component.proxy, addr)
          if ok2 and px and px.getLabel and px.getLabel() == target then
            candidates[#candidates + 1] = addr
          end
        end
      end
      -- #SEC M-10 — the address-prefix path was non-deterministic (it took
      -- whatever component.list() yielded first, which OC does not order
      -- stably). An exact single match is fine; an ambiguous prefix that
      -- matches several devices is refused rather than silently mounting a
      -- coin-flip device.
      local found = nil
      if #addrMatches == 1 then
        found = addrMatches[1]
      elseif #addrMatches > 1 then
        table.sort(addrMatches)
        o(string.format("Ambiguous address prefix '%s' matches %d devices (%s, ...); use a longer prefix",
          target, #addrMatches, addrMatches[1]:sub(1, 8) .. "..."), T.error)
        return
      end
      if not found and #candidates > 0 then
        table.sort(candidates)  -- stable lexicographic order
        found = candidates[1]
        if #candidates > 1 then
          o(string.format("Note: %d disks share label '%s'; mounting %s (use partial address to disambiguate)",
            #candidates, target, found:sub(1, 8) .. "..."), T.warning)
        end
      end
      if not found then o("Device not found: " .. target, T.error); return end
      local mnt = mntArg:sub(1,1) == "/" and mntArg or ("/" .. mntArg)
      local ok2, px2 = pcall(component.proxy, found)
      if not ok2 then o("Cannot proxy device", T.error); return end
      if not F.exists(mnt) then pcall(F.makeDirectory, mnt) end
      -- securefs.mount requires an explicit session arg (otherwise the
      -- admin check sees no session and denies). Resolve the active
      -- session from the user module and pass it through.
      local sess = helpers.sessionOf(S)  -- #SEC CR-9 — seat-bound principal
      local mok, merr = F.mount(mnt, px2, sess)
      if mok == false then
        o(tostring(merr or "Mount failed"), T.error); return
      end
      S.lastOut = { "Mounted at " .. mnt, T.highlight }
    else
      local mnts = F.mounts()
      o(string.format(" %-18s %-14s %s", "Mount", "Label", "Space"), T.title)
      o(string.rep("-", 46), T.dim)
      for _, m in ipairs(mnts) do
        local kb = m.total and math.floor(m.total/1024) or 0
        local used = m.used and math.floor(m.used/1024) or 0
        o(string.format(" %-18s %-14s %dK/%dK",
          (m.mountPoint or "?"):sub(1,18),
          (m.label or ""):sub(1,14),
          used, kb), T.fg)
      end
    end
  end

  C.umount = function(args, o)
    if not args[1] then o("Usage: umount <mountpoint>", T.dim); return end
    if not adminOnly(o) then return end
    local mnt = args[1]:sub(1,1) == "/" and args[1] or ("/" .. args[1])
    local sess = helpers.sessionOf(S)  -- #SEC CR-9 — seat-bound principal
    local ok2, err2 = F.unmount(mnt, sess)
    if ok2 then S.lastOut = { "Unmounted " .. mnt, T.highlight }
    else      S.lastOut = { tostring(err2 or "Failed to unmount"), T.error } end
  end

  -- JBOD disk pooling (opt-in feature; the kernel module only exists when
  -- /etc/boot.cfg has advanced.jbod = true). Hidden from `help` otherwise.
  C.jbod = function(args, o)
    local jb = K.getJBOD and K.getJBOD()
    if not jb then
      o("JBOD is disabled. Enable it with: bootsettings jbod on  (then reboot)", T.warning)
      o("It pools several disks into one mount. See 'man jbod'.", T.dim)
      return
    end
    local sub = (args[1] or "list"):lower()

    -- Resolve a user-typed disk reference (address prefix or label) to a
    -- full filesystem-component address. Mirrors the `mount` command's
    -- deterministic matching so duplicate labels don't flip-flop.
    local function resolveFs(ref)
      local addrMatches, labelMatches = {}, {}
      for addr in component.list("filesystem") do
        if addr:sub(1, #ref) == ref then
          addrMatches[#addrMatches + 1] = addr
        else
          local ok2, px = pcall(component.proxy, addr)
          if ok2 and px and px.getLabel and px.getLabel() == ref then
            labelMatches[#labelMatches + 1] = addr
          end
        end
      end
      table.sort(addrMatches); table.sort(labelMatches)
      if #addrMatches == 1 then return addrMatches[1] end
      if #addrMatches == 0 and #labelMatches == 1 then return labelMatches[1] end
      if #addrMatches > 1 then return nil, "ambiguous address prefix: " .. ref end
      if #labelMatches > 1 then return nil, "ambiguous label: " .. ref end
      return nil, "no filesystem matches: " .. ref
    end

    if sub == "list" or sub == "status" then
      local cfg = jb.loadConfig(F) or { pools = {} }
      local pools = cfg.pools or {}
      if #pools == 0 then o("No JBOD pools configured.", T.dim) end
      for _, p in ipairs(pools) do
        local present = 0
        for _, a in ipairs(p.members or {}) do
          for live in component.list("filesystem") do
            if live == a then present = present + 1; break end
          end
        end
        o(string.format(" %-16s %d member(s), %d present",
          p.mount, #(p.members or {}), present), T.fg)
      end
      o("Free space: df  ·  individual disks: disk  ·  manage: jbod create|destroy", T.dim)

    elseif sub == "create" then
      if not adminOnly(o) then return end
      local mount = args[2]
      if not mount or not args[3] then
        o("Usage: jbod create <mountpoint> <disk> [disk...]", T.dim)
        o("  <disk> = fs address prefix or label (see lsdev)", T.dim)
        return
      end
      if mount:sub(1, 1) ~= "/" then mount = "/" .. mount end
      mount = (F.normalize and F.normalize(mount)) or mount
      -- #REV (#7) — confine pools to /mnt/ and MAKE the mount point a real
      -- directory. Previously any string was accepted: a pool at "/mnt/pool"
      -- mounted even though neither /mnt nor pool existed, so the path was
      -- invisible in the browser and behaved confusingly.
      if not (mount:sub(1, 6) == "/mnt/" and #mount > 6) then
        o("JBOD mount point must be under /mnt/  (e.g. jbod create /mnt/pool ...)", T.error)
        return
      end
      -- Build member proxies from the requested disks.
      local bootAddr = _G._TOS and _G._TOS.bootAddr
      local members, addrs = {}, {}
      for i = 3, #args do
        local addr, rerr = resolveFs(args[i])
        if not addr then o(tostring(rerr), T.error); return end
        -- #REV (#7) — refuse the BOOT disk as a pool member. Pooling it
        -- exposed the whole TOS install inside the pool ("cd /mnt/pool
        -- showed a copy of TOS") and risks the system files. Data disks only.
        if bootAddr and addr == bootAddr then
          o("Refusing to pool the BOOT disk (" .. addr:sub(1, 8) .. "...).", T.error)
          o("It would expose the system files inside the pool. Use data disks.", T.dim)
          return
        end
        local ok2, px = pcall(component.proxy, addr)
        if not ok2 or not px then o("Cannot open disk: " .. args[i], T.error); return end
        members[#members + 1] = px
        addrs[#addrs + 1] = addr
      end
      -- Create the mount path (and /mnt) so it's a real, visible directory.
      pcall(F.makeDirectory, "/mnt")
      pcall(F.makeDirectory, mount)
      local proxy = jb.makePool(members)
      local sess = helpers.sessionOf(S)
      local mok, merr = F.mount(mount, proxy, sess)
      if not mok then o(tostring(merr or "Mount failed"), T.error); return end
      -- Persist so the pool re-mounts on the next boot.
      local cfg = jb.loadConfig(F) or { pools = {} }
      cfg.pools = cfg.pools or {}
      -- Replace any existing entry for this mount point.
      for i = #cfg.pools, 1, -1 do
        if cfg.pools[i].mount == mount then table.remove(cfg.pools, i) end
      end
      cfg.pools[#cfg.pools + 1] = { mount = mount, members = addrs }
      jb.saveConfig(F, cfg)
      S.lastOut = { string.format("JBOD pool at %s (%d disks)", mount, #addrs), T.highlight }

    elseif sub == "destroy" or sub == "remove" then
      if not adminOnly(o) then return end
      local mount = args[2]
      if not mount then o("Usage: jbod destroy <mountpoint>", T.dim); return end
      if mount:sub(1, 1) ~= "/" then mount = "/" .. mount end
      local sess = helpers.sessionOf(S)
      F.unmount(mount, sess)  -- best-effort; may already be unmounted
      local cfg = jb.loadConfig(F) or { pools = {} }
      local removed = false
      for i = #(cfg.pools or {}), 1, -1 do
        if cfg.pools[i].mount == mount then table.remove(cfg.pools, i); removed = true end
      end
      if removed then jb.saveConfig(F, cfg) end
      S.lastOut = { removed and ("Destroyed JBOD pool " .. mount)
        or ("No JBOD pool at " .. mount), removed and T.highlight or T.warning }

    else
      o("Usage: jbod [list | create <mount> <disk...> | destroy <mount>]", T.dim)
    end
  end

  -- Remote filesystem shares. Two halves that are easy to confuse, so the
  -- command keeps them visibly apart:
  --   SERVING  — what this machine exports, from /etc/netfs-exports.cfg,
  --              and whether the netfsd service has actually armed it.
  --   MOUNTED  — remote shares this machine has attached.
  -- A share is someone else's disk: when their computer is off the mount
  -- is empty and the files vanish from a listing without being deleted.
  C.netfs = function(args, o)
    local okNF, nf = pcall(require, "kernel.netfs")
    if not okNF or not nf then
      o("netfs module unavailable on this system.", T.error)
      return
    end
    local sub = (args[1] or "status"):lower()

    -- Active netfs mounts are discoverable from the mount table itself —
    -- attach() stamps a "netfs:" address — so the command keeps no state
    -- of its own that could drift from reality.
    local function netfsMounts()
      local out = {}
      for _, m in ipairs(F.mounts() or {}) do
        if type(m.address) == "string" and m.address:sub(1, 6) == "netfs:" then
          out[#out + 1] = m
        end
      end
      table.sort(out, function(a, b) return a.mountPoint < b.mountPoint end)
      return out
    end

    if sub == "status" or sub == "list" then
      -- Serving side. Exports configured but service stopped is the
      -- confusing state, so say so rather than listing them as if live.
      local serving = nf.isEnabled and nf.isEnabled()
      local exports = nf.getExports and nf.getExports() or {}
      o("Serving: " .. (serving and "yes" or "no (service netfsd is not running)"),
        serving and T.highlight or T.warning)
      if #exports == 0 then
        o("  No exports configured (" .. nf.EXPORTS_PATH .. ").", T.dim)
      else
        for _, e in ipairs(exports) do
          o(string.format("  %-12s %-24s %s  %d peer rule(s)",
            e.name, e.path, e.mode, #(e.allow or {})), T.fg)
        end
      end

      local mounted = netfsMounts()
      o("", T.fg)
      if #mounted == 0 then
        o("Mounted: none", T.dim)
      else
        o("Mounted:", T.fg)
        for _, m in ipairs(mounted) do
          -- A host that has gone away still has a mount entry; its
          -- capacity reads as zero, which is the honest signal.
          local live = (m.total or 0) > 0
          o(string.format("  %-16s %-22s %s", m.mountPoint, m.label,
            live and fmtSz(m.total - (m.used or 0)) .. " free" or "unreachable"),
            live and T.fg or T.warning)
        end
      end
      o("Manage: netfs mount <host> <share> <mountpoint> · netfs umount <mountpoint>", T.dim)

    elseif sub == "exports" then
      -- Re-read from disk so an operator can check a file they just
      -- edited without restarting the service to find out it is invalid.
      local ok2, err2 = nf.loadExports(F)
      if not ok2 then
        o("Export file rejected: " .. tostring(err2), T.error)
        o("Nothing is served while the file is invalid.", T.dim)
        return
      end
      local exports = nf.getExports()
      if #exports == 0 then
        o("No exports in " .. nf.EXPORTS_PATH, T.dim)
        o("Format: { { name=\"pub\", path=\"/srv/pub\", mode=\"ro\", allow={\"<addr>\"} } }", T.dim)
        return
      end
      for _, e in ipairs(exports) do
        o(string.format("%-12s %-24s %s", e.name, e.path, e.mode), T.highlight)
        for _, a in ipairs(e.allow or {}) do
          o("    allow " .. a, T.dim)
        end
        if #(e.allow or {}) == 0 then
          o("    allow (none) — this export is unreachable", T.warning)
        end
      end
      o("Changes take effect on: service restart netfsd", T.dim)

    elseif sub == "mount" then
      if not adminOnly(o) then return end
      local host, share, mount = args[2], args[3], args[4]
      if not (host and share and mount) then
        o("Usage: netfs mount <host> <share> <mountpoint>", T.dim)
        o("  <host>  = peer hostname or address prefix (see net peers)", T.dim)
        o("  <share> = export name on that machine (ask its operator)", T.dim)
        return
      end
      if not NM then o("Networking is not available.", T.error); return end

      -- Resolve a hostname or address prefix the same way `share` does.
      local addr = host
      local peer = NM.findPeer and NM.findPeer(host)
      if peer and peer.addr then addr = peer.addr end

      -- The server refuses anything below TRUSTED, but failing here with
      -- the real reason beats a timeout the operator has to guess at.
      if NM.getTrust or NM.getProtocol then
        local okT, trustMod = pcall(require, "kernel.net.trust")
        if okT and trustMod and trustMod.getLevel and trustMod.LEVEL then
          if trustMod.getLevel(addr) < trustMod.LEVEL.TRUSTED then
            o("Peer is not TRUSTED — netfs refuses to mount from it.", T.error)
            o("Raise trust first (see 'net trust'), then retry.", T.dim)
            return
          end
        end
      end

      -- Same rule as jbod pools: under /mnt/ only, so a share can never
      -- shadow a system path and is visible where people look for it.
      if not (mount:sub(1, 5) == "/mnt/" and #mount > 5) then
        o("Mount point must be under /mnt/  (e.g. netfs mount box pub /mnt/box)", T.error)
        return
      end

      local proxy = nf.attach(addr, share)
      -- Probe before mounting. attach() is lazy — it opens no connection —
      -- so without this, a wrong share name mounts "successfully" and only
      -- fails later, when the operator is no longer looking at this command.
      local probe = proxy.spaceTotal and proxy.spaceTotal() or 0
      if not proxy.exists("/") and probe == 0 then
        o("Cannot reach share '" .. share .. "' on " .. tostring(addr):sub(1, 8) .. ".", T.error)
        o("Check the export name, and that netfsd runs there and allows this machine.", T.dim)
        return
      end

      pcall(F.makeDirectory, "/mnt")
      pcall(F.makeDirectory, mount)
      local sess = helpers.sessionOf(S)
      local mok, merr = F.mount(mount, proxy, sess)
      if not mok then o(tostring(merr or "Mount failed"), T.error); return end
      o("Mounted " .. share .. " from " .. tostring(addr):sub(1, 8) .. " at " .. mount,
        T.highlight)
      o("This mount is only usable while that machine is online.", T.dim)

    elseif sub == "umount" then
      if not adminOnly(o) then return end
      local mount = args[2]
      if not mount then o("Usage: netfs umount <mountpoint>", T.dim); return end
      local found = false
      for _, m in ipairs(netfsMounts()) do
        if m.mountPoint == mount then found = true; break end
      end
      if not found then
        o("No netfs mount at " .. mount, T.warning)
        o("Use 'netfs status' to list them (plain 'umount' handles local disks).", T.dim)
        return
      end
      local sess = helpers.sessionOf(S)
      local ok2, err2 = F.unmount(mount, sess)
      if ok2 then o("Unmounted " .. mount, T.highlight)
      else o(tostring(err2 or "Failed to unmount"), T.error) end

    else
      o("Usage: netfs [status | exports | mount <host> <share> <mount> | umount <mount>]",
        T.dim)
    end
  end

  C.theme = function(args, o)
    -- #SEC C7 — `theme set` writes through themeMod.saveForUser(sess)
    -- which persists to the current user's home, but the system-wide
    -- side effects of setting THEME (status bar, every redraw) are
    -- destructive to the current display context. Read-only `theme`
    -- with no args is still informational; mutating subcommands need
    -- admin tier. We gate after the manager-availability check so the
    -- "theme manager unavailable" message is still surfaced first.
    local themeMod = _G._TOS and _G._TOS.theme
    if not themeMod then
      o("Theme manager unavailable (T1 / monochrome or low-RAM boot)", T.warning)
      return
    end
    -- #FIX (per-user themes) — any regular user may pick a PRESET theme for
    -- THEIR OWN session (saved to ~/.theme.cfg, restored at their next login).
    -- Only CUSTOM colour overrides remain admin-gated ("preset ones and stuff
    -- root allows if they're custom"). Read-only views are open to anyone.
    do
      local sub0 = (args[1] or "show"):lower()
      local READONLY = { list = true, ls = true, show = true, current = true, keys = true, [""] = true }
      local CUSTOM   = { color = true, colour = true }
      if CUSTOM[sub0] then
        if not adminOnly(o) then return end
      elseif not READONLY[sub0] then
        -- Applying / resetting a preset is a personal action; require a real
        -- (USER+) login so a transient GUEST/kiosk session can't repaint a
        -- shared screen.
        if helpers.liveTier(S) < 1 then
          o("Log in as a user to set a personal theme.", T.error); return
        end
      end
    end

    local function parseColor(s)
      if not s then return nil end
      -- Accept 0xFF8800, #FF8800, FF8800, or plain decimal.
      -- #SEC M19 — limit input length so a multi-megabyte string can't
      -- consume the parser. The largest legitimate form is "0xFFFFFF" (8).
      if type(s) ~= "string" or #s > 16 then return nil end
      local hex = s:match("^0[xX](%x+)$") or s:match("^#(%x+)$") or s:match("^(%x+)$")
      if hex and #hex <= 6 then return tonumber(hex, 16) end
      return tonumber(s)
    end

    local function fmtHex(n) return string.format("0x%06X", n) end

    local sub = args[1] and args[1]:lower() or "show"
    -- #SEC CR-9 — save to the SEAT-bound user, not the global currentSession
    -- (which in multi-seat is some other seat's session). This is what makes
    -- "each user's own theme" correct on login restore.
    local sess = helpers.sessionOf(S)

    if sub == "list" or sub == "ls" then
      o("Available themes:", T.title)
      for _, name in ipairs(themeMod.list()) do
        local marker = (name == themeMod.current().preset) and " *" or "  "
        o(string.format(" %s %-10s %s", marker, name, themeMod.describe(name) or ""), T.fg)
      end
      o("", T.fg)
      o("'*' = currently active.  Use 'theme set <name>' to switch.", T.dim)

    elseif sub == "show" or sub == "current" then
      local cur = themeMod.current()
      o("Active theme: " .. cur.preset, T.title)
      o("  " .. (themeMod.describe(cur.preset) or ""), T.dim)
      local cnt = 0
      for _ in pairs(cur.overrides) do cnt = cnt + 1 end
      if cnt == 0 then
        o("No color overrides.", T.dim)
      else
        o("Overrides:", T.highlight)
        for k, v in pairs(cur.overrides) do
          o(string.format("  %-14s %s", k, fmtHex(v)), T.fg)
        end
      end
      o("", T.fg)
      o("Try: theme set <name>  |  theme color <key> <0xRRGGBB>  |  theme reset", T.dim)

    elseif sub == "set" or sub == "use" then
      local name = args[2]
      if not name then o("Usage: theme set <name>  (theme list to see names)", T.warning); return end
      local ok, err = themeMod.apply(name)
      if not ok then o(err or "apply failed", T.error); return end
      o("Applied theme: " .. name, T.highlight)
      if sess then
        local sOk, sErr = themeMod.saveForUser(sess)
        if not sOk then o("(not saved: " .. tostring(sErr) .. ")", T.dim) end
      end
      deps.drawAll()

    elseif sub == "preview" or sub == "try" then
      local name = args[2]
      if not name then o("Usage: theme preview <name>", T.warning); return end
      local ok, err = themeMod.apply(name)
      if not ok then o(err or "apply failed", T.error); return end
      o("Previewing '" .. name .. "' (not saved). Use 'theme set' to keep it.", T.highlight)
      deps.drawAll()

    elseif sub == "color" or sub == "colour" then
      local key, val = args[2], args[3]
      if not key or not val then
        o("Usage: theme color <key> <0xRRGGBB>", T.warning)
        o("Keys: " .. table.concat(themeMod.overridableKeys(), ", "), T.dim)
        return
      end
      if not themeMod.isOverridable(key) then
        o("Not an overridable color: " .. key, T.error)
        o("Run 'theme color' with no args for the full list.", T.dim)
        return
      end
      local n = parseColor(val)
      if not n then o("Invalid color value: " .. val .. " (try 0xFF8800)", T.error); return end
      local ok, err = themeMod.setColor(key, n)
      if not ok then o(err or "color set failed", T.error); return end
      o(string.format("%s = %s", key, fmtHex(n)), T.highlight)
      if sess then themeMod.saveForUser(sess) end
      deps.drawAll()

    elseif sub == "reset" then
      local ok, err = themeMod.resetOverrides()
      if not ok then o(err or "reset failed", T.error); return end
      o("Cleared color overrides; preset '" .. themeMod.current().preset .. "' restored.", T.highlight)
      if sess then themeMod.saveForUser(sess) end
      deps.drawAll()

    elseif sub == "clear" or sub == "default" then
      if not sess then o("Not logged in.", T.error); return end
      local ok, err = themeMod.clearForUser(sess)
      if not ok then o(err or "clear failed", T.error); return end
      o("Theme reset to default; saved preference cleared.", T.highlight)
      deps.drawAll()

    elseif sub == "keys" then
      o("Overridable color keys:", T.title)
      for _, k in ipairs(themeMod.overridableKeys()) do o("  " .. k, T.fg) end

    else
      o("Usage: theme <list|show|set|preview|color|reset|clear|keys>", T.warning)
      o("  list                  Show available themes", T.dim)
      o("  show                  Show active theme + overrides", T.dim)
      o("  set <name>            Apply preset and save for this user", T.dim)
      o("  preview <name>        Apply preset without saving", T.dim)
      o("  color <key> <0xRGB>   Override a single color", T.dim)
      o("  keys                  List overridable color keys", T.dim)
      o("  reset                 Drop overrides, keep preset", T.dim)
      o("  clear                 Wipe saved theme, revert to default", T.dim)
    end
  end
  C.colors = C.theme
  C.service = function(args, o)
    if not adminOnly(o) then return end
    local ok2, rcMod = pcall(require, "kernel.rc")
    if not ok2 then o("RC module unavailable", T.error); return end
    if not args[1] then
      local svcs = rcMod.list()
      if #svcs == 0 then o("No services registered", T.dim); return end
      o(string.format(" %-16s %s", "Service", "Status"), T.title)
      o(string.rep("-", 28), T.dim)
      for _, s in ipairs(svcs) do
        local st2 = s.running and "running" or "stopped"
        o(string.format(" %-16s %s", s.name:sub(1,16), st2),
          s.running and T.highlight or T.dim)
      end
    elseif args[1] == "start" and args[2] then
      local ok3, err = rcMod.start(args[2])
      o(ok3 and "Started: " .. args[2] or tostring(err), ok3 and T.highlight or T.error)
    elseif args[1] == "stop" and args[2] then
      local ok3, err = rcMod.stop(args[2])
      o(ok3 and "Stopped: " .. args[2] or tostring(err), ok3 and T.highlight or T.error)
    else
      o("Usage: service [start|stop <name>]", T.dim)
    end
  end

  -- ── Scheduled tasks ───────────────────────────────────
  C.cron = function(args, o)
    if not adminOnly(o) then return end
    local ok2, cronMod = pcall(require, "kernel.cron")
    if not ok2 then o("Cron module unavailable", T.error); return end
    if not args[1] or args[1] == "list" then
      local jobs = cronMod.list()
      if #jobs == 0 then o("No scheduled jobs", T.dim); return end
      o(string.format(" %-4s %-16s %-8s %s", "ID", "Name", "Every", "Enabled"), T.title)
      for _, j in ipairs(jobs) do
        o(string.format(" %-4d %-16s %-8s %s",
          j.id, j.name:sub(1,16), j.interval.."s", j.enabled and "yes" or "no"),
          j.enabled and T.fg or T.dim)
      end
    elseif args[1] == "add" and args[2] and args[3] and args[4] then
      local name = args[2]
      local interval = tonumber(args[3])
      local script = table.concat(args, " ", 4)
      if not interval then o("Invalid interval", T.error); return end
      local id = cronMod.add(name, interval, script)
      o("Added job #" .. id .. ": " .. name, T.highlight)
    elseif args[1] == "rm" and args[2] then
      local id = tonumber(args[2])
      if id then
        local rok, rerr = cronMod.remove(id)
        if rok then o("Removed job #" .. id, T.highlight)
        else o("cron rm: " .. tostring(rerr or "no such job"), T.error) end
      else o("Invalid ID", T.error) end
    else
      o("Usage: cron [list|add <name> <seconds> <script>|rm <id>]", T.dim)
    end
  end

end

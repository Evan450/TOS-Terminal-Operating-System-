-- kernel.internet's absence path and kill switch, on a real boot.
--
-- Ports the two bullets from the INTERNET CARD + REMOTE PKG round's
-- emulator checklist that do NOT need a live card or a server with HTTP
-- turned on: "no card: `internet` reports / `pkg fetch` fails cleanly",
-- and half of "`internet off/on` toggle" (the off half -- the on half
-- needs a real card to prove anything). Everything else on that
-- checklist (repo add against a live server, hashless-repo refusal, the
-- byte cap near a T1's ceiling, pulling the card mid-download) needs
-- hardware or a second machine and stays manual.
--
-- The off-box test for this module drives a FAKE component list, which
-- can say "no card" as easily as it can say anything else. What it
-- cannot prove is that internet.status() on THIS machine, against
-- component.list as OpenComputers actually implements it, agrees -- or
-- that a request against the real absence path returns a clean error
-- instead of throwing, which is the difference between "no internet"
-- and "the machine you're on jams a caller that didn't pcall a network
-- call".
return function(t)
  local okI, internet = pcall(require, "kernel.internet")
  if not okI or type(internet) ~= "table" then
    return t.skip("internet", "kernel.internet unavailable")
  end

  local st = internet.status()
  t.ok("status() returns a table", type(st) == "table")

  if type(st) == "table" and not st.present then
    t.ok("no card -> a real reason is given, not a bare false",
      type(st.reason) == "string" and #st.reason > 0)
    t.ok("no card -> available() agrees", internet.available() == false)

    -- A request against the absent-card path must fail CLEANLY: an
    -- error string handed back, never a thrown Lua error a caller has
    -- to wrap in pcall to survive.
    local okG, body, err = pcall(internet.get, "http://example.invalid/probe")
    t.ok("get() with no card does not throw", okG)
    if okG then
      t.eq("...and returns no body", nil, body)
      t.ok("...with a reason", type(err) == "string" and #err > 0)
    end
  else
    -- A real card is plugged into this box this round. Nothing wrong
    -- with that -- there is just nothing this half of the check can
    -- prove without a live server on the other end, which is the other
    -- (manual) half of the same checklist item.
    t.skip("no-card path", "a real internet card is present on this machine")
  end

  -- The kill switch does not depend on hardware at all: it is a config
  -- read, so it is provable on every machine regardless of what happens
  -- to be plugged in this round.
  local okC, config = pcall(require, "kernel.config")
  if not (okC and config and config.get and config.set) then
    return t.skip("kill switch", "kernel.config unavailable")
  end

  -- config.set() is in-memory only -- config.save() is a separate call
  -- this never makes -- so this can flip the switch and put it back
  -- without ever touching /etc/tos.cfg on disk.
  local had = config.get("internet")
  local ok, err = pcall(function()
    config.set("internet", false)
    t.ok("isEnabled() honours the switch turned off", internet.isEnabled() == false)
    t.ok("...and available() agrees", internet.available() == false)
    local stOff = internet.status()
    if stOff.present then
      t.ok("switched off -> the reason names the switch, not the card",
        type(stOff.reason) == "string"
          and stOff.reason:find("disabled on this machine", 1, true) ~= nil)
    end

    config.set("internet", true)
    t.ok("isEnabled() flips back on", internet.isEnabled() == true)
  end)
  config.set("internet", had)
  t.eq("config left exactly as found", had, config.get("internet"))
  if not ok then t.ok("kill-switch check: " .. tostring(err), false) end
end

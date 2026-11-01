-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Discover! Interactive
-- ╔═══════════════════════════════════════════════════════════╗
-- ║  TOS Kernel - Security policy loader                       ║
-- ║                                                            ║
-- ║  Everything that enforces kernel/policy.lua gets it        ║
-- ║  through here. If it will not load, each table comes back  ║
-- ║  empty, or refusing everything, so a broken policy can     ║
-- ║  only ever take authority away. This file stays this       ║
-- ║  small so that it is not the thing that breaks.            ║
-- ╚═══════════════════════════════════════════════════════════╝

local cached

local DENY_ALL = setmetatable({}, { __index = function() return true end })

local function closed()
  return {
    closed = true,
    MODULE_PREFIXES = {}, MODULE_NAMES = {}, BLOCKED_MODULES = DENY_ALL,
    BASE_COMPONENTS = {}, GATED_COMPONENTS = {}, SERVICE_PORTS = DENY_ALL,
    PKG_RUN_CAPS = {}, SERVICE_DEFAULT_CAPS = {}, SERVICE_CAPS = {},
    KERNEL_REQUIRE_ALLOW = {}, KERNEL_SERVICES = {},
    isAdmin = function(session)
      return type(session) == "table" and session.isKernel == true
    end,
  }
end

--- The policy, for `who` to enforce. Said once, as loudly as the moment
--- allows: this runs early enough that the log may not exist yet.
return function(who)
  if cached then return cached end
  local ok, policy = pcall(require, "kernel.policy")
  if ok and type(policy) == "table" then
    cached = policy
    return cached
  end
  cached = closed()
  local message = "SECURITY POLICY DID NOT LOAD (" .. tostring(who) .. "): "
    .. tostring(policy) .. ". Everything non-kernel is denied until it is repaired."
  local log = package.loaded["kernel.log"]
  if type(log) == "table" and log.error then pcall(log.error, "policy", message) end
  _G._TOS_POLICY_FAILURE = message
  return cached
end

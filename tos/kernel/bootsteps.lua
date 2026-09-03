-- ╔══════════════════════════════════════════════════════════╗
-- ║  TOS Kernel - Boot Step Narration                         ║
-- ║                                                            ║
-- ║  Maps a raw kernel boot-log message to a friendly HIGH-    ║
-- ║  LEVEL step for the splash loading bar's narration (e.g.   ║
-- ║  "OpenOS compat: 11 modules loaded" -> "Loading OpenOS     ║
-- ║  compatibility layer"). The many internal "<x> module      ║
-- ║  ready" lines collapse into a handful of clean stages, so  ║
-- ║  a quiet "splash" boot still tells the operator what TOS   ║
-- ║  is doing — without dumping the full text log.             ║
-- ║                                                            ║
-- ║  Pure + dependency-free (loads at early boot). If a kernel ║
-- ║  message is later reworded and stops matching, its step    ║
-- ║  simply drops out of the narration — the bar is unaffected.║
-- ╚══════════════════════════════════════════════════════════╝

local bootsteps = {}

-- Ordered { substring, friendly-step } pairs. FIRST substring the message
-- contains wins, so put more specific entries before broader ones.
bootsteps.STAGES = {
  { "Scanning hardware",       "Scanning hardware"                  },
  { "Initializing filesystem", "Mounting filesystems"               },
  { "Boot disk",               "Mounting filesystems"               },
  { "Loading configuration",   "Loading configuration"              },
  { "Starting event",          "Starting event system"             },
  { "Starting process",        "Starting process manager"          },
  { "Initializing display",    "Initializing display"               },
  { "Crypto",                  "Initializing cryptography"          },
  { "User system",             "Loading users and security"         },
  { "Security",                "Loading users and security"         },
  { "Theme manager",           "Loading themes"                     },
  { "Trust manager",           "Starting networking"                },
  { "Network",                 "Starting networking"                },
  { "transfer",                "Starting networking"                },
  { "Remote shell",            "Starting networking"                },
  { "Loading:",                "Starting background services"       },
  { "Service started",         "Starting background services"       },
  { "Startup services",        "Starting background services"       },
  { "Cron",                    "Starting scheduler"                 },
  { "Package manager",         "Loading package manager"            },
  { "OpenOS compat",           "Loading OpenOS compatibility layer" },
  { "Audio feedback",          "Enabling audio feedback"            },
  { "Boot complete",           "Boot complete"                      },
}

-- Number of DISTINCT friendly stages. The splash loading bar uses this as its
-- denominator so the bar tracks the boot NARRATIVE (stages reached) rather than
-- the raw INFO-line count, which varies a lot by config (a data-card + network
-- box emits far more lines than a minimal one) and used to saturate the bar
-- long before boot actually finished. Computed, so adding a stage stays correct.
do
  local seen, n = {}, 0
  for _, s in ipairs(bootsteps.STAGES) do
    if not seen[s[2]] then seen[s[2]] = true; n = n + 1 end
  end
  bootsteps.STAGE_COUNT = n
end

--- Friendly step for a raw boot message, or nil if none matches.
function bootsteps.stageFor(msg)
  msg = tostring(msg or "")
  for _, s in ipairs(bootsteps.STAGES) do
    if msg:find(s[1], 1, true) then return s[2] end
  end
  return nil
end

--- Dedup helper: the step to SHOW given the previously-shown step and a new
--- message, or nil when there's nothing new (unmatched, or the same step as
--- last time). Lets the caller collapse runs of the same stage into one line.
function bootsteps.next(prevStage, msg)
  local s = bootsteps.stageFor(msg)
  if s and s ~= prevStage then return s end
  return nil
end

--! Where the splash loading bar goes, for a screen of THIS size.
--!
--! Pure and here rather than inline in /init.lua because it has to be
--! recomputed, and the bug was that it wasn't. The boot file reads the
--! resolution once, right after gpu.bind(), which in OpenComputers leaves the
--! screen at its MAXIMUM. The kernel then applies the resolution policy from
--! kernel/screen.lua -- density-based, floored at 80x25 -- and on a Tier 3
--! GPU driving a multi-block screen that is a genuine reduction: 160x50 down
--! to 80x25. Every later draw still used the 160 it measured at the start, so
--! the bar centred itself at column 60 of a screen 80 wide and ran off the
--! right-hand edge, taking the wordmark above it with it.
--!
--! It only shows on Tier 3 AND a screen bigger than one block, which is
--! exactly the combination it was reported on: a Tier 2 GPU maxes at 80x25 and
--! a single Tier 3 block at 50x16, so in both cases the policy asks for what
--! is already set and nothing moves.
--!
--! @param screenW,screenH  the LIVE resolution, not the one measured at boot
--! @param headerBottom     last row the wordmark/status block used
--! @return barRow, barW, barX
function bootsteps.splashGeometry(screenW, screenH, headerBottom)
  screenW = (type(screenW) == "number" and screenW > 0) and math.floor(screenW) or 50
  screenH = (type(screenH) == "number" and screenH > 0) and math.floor(screenH) or 16
  headerBottom = (type(headerBottom) == "number") and math.floor(headerBottom) or 1
  local barW = math.max(10, math.min(40, screenW - 6))
  -- barW+2 counts the [ ] brackets. Clamp to 1 so a screen narrower than the
  -- minimum bar starts at the left edge rather than at column zero.
  local barX = math.max(1, math.floor((screenW - (barW + 2)) / 2) + 1)
  local barRow = math.min(screenH - 4, headerBottom + 1)
  if barRow < 1 then barRow = 1 end
  return barRow, barW, barX
end

--- Does that bar actually fit on that screen? The property the bug broke.
function bootsteps.splashFits(screenW, screenH, headerBottom)
  local barRow, barW, barX = bootsteps.splashGeometry(screenW, screenH, headerBottom)
  return (barX >= 1) and (barX + barW + 1 <= screenW)
     and (barRow >= 1) and (barRow <= screenH)
end

return bootsteps

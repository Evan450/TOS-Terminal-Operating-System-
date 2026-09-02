local bootsteps = {}

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

do
  local seen, n = {}, 0
  for _, s in ipairs(bootsteps.STAGES) do
    if not seen[s[2]] then seen[s[2]] = true; n = n + 1 end
  end
  bootsteps.STAGE_COUNT = n
end

function bootsteps.stageFor(msg)
  msg = tostring(msg or "")
  for _, s in ipairs(bootsteps.STAGES) do
    if msg:find(s[1], 1, true) then return s[2] end
  end
  return nil
end

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

  local barX = math.max(1, math.floor((screenW - (barW + 2)) / 2) + 1)
  local barRow = math.min(screenH - 4, headerBottom + 1)
  if barRow < 1 then barRow = 1 end
  return barRow, barW, barX
end

function bootsteps.splashFits(screenW, screenH, headerBottom)
  local barRow, barW, barX = bootsteps.splashGeometry(screenW, screenH, headerBottom)
  return (barX >= 1) and (barX + barW + 1 <= screenW)
     and (barRow >= 1) and (barRow <= screenH)
end

return bootsteps

--! The mapping is COMPUTED, not tabulated. OpenOS's lib/note.lua builds a
--! 75-entry name->MIDI table at load time (a0 through b6, MIDI 21-95) plus
--! a reverse table plus a third pass for the flat names. That is ~2 KB of
--! table on a box where the whole compat layer has to justify its bytes,
--! and every entry is derivable: MIDI = 12 * (octave + 1) + semitone.
--! Checked against their table at the edges and in the middle --
--! a0 = 21, bb0 = 22, c4 = 60, a4 = 69, b6 = 95 -- and the RANGE is theirs
--! deliberately: 21-95 is what fits computer.beep, so a name outside it
--! must raise exactly as it does on OpenOS rather than return a frequency
--! the sound card will refuse. (test_compat_note.lua)

local computer = require("computer")

local note = {}

local SEMITONE = { c = 0, d = 2, e = 4, f = 5, g = 7, a = 9, b = 11 }

local SHARP_NAME = {
  [0] = "C", [1] = "C#", [2] = "D",  [3] = "D#", [4] = "E",  [5] = "F",
  [6] = "F#", [7] = "G", [8] = "G#", [9] = "A", [10] = "A#", [11] = "B",
}

local MIDI_MIN, MIDI_MAX = 21, 95

--! A beep BLOCKS the machine for its whole duration (see the beep item in
--! TODO.txt), and on a multi-seat box that stalls every other seat too. A
--! deliberate departure from OpenOS, which passes the duration straight
--! through: we clamp. Five seconds is already an eternity for a note and
--! it keeps `note.play("c4", 600)` from being a denial of service that any
--! sandboxed program can call.
local MAX_PLAY_SECONDS = 5

local function nameToMidi(s)
  local letter, accidental, octave = s:lower():match("^([a-g])([#b]?)(%d+)$")
  if not letter then return nil end
  local midi = 12 * (tonumber(octave) + 1) + SEMITONE[letter]
  if accidental == "#" then midi = midi + 1
  elseif accidental == "b" then midi = midi - 1 end
  if midi < MIDI_MIN or midi > MIDI_MAX then return nil end
  return midi
end

local BAD_NAME = " given to note.%s, needs to be <note>[semitone sign]" ..
                 "<octave>, e.g. A#0 or Gb4"

function note.midi(n)
  if type(n) == "string" then
    local midi = nameToMidi(n)
    if not midi then
      error("Wrong input " .. tostring(n) .. BAD_NAME:format("midi"), 2)
    end
    return midi
  elseif type(n) == "number" then
    return math.floor((12 * math.log(n / 440, 2)) + 69)
  end
  error("Wrong input " .. tostring(n) ..
        " given to note.midi, needs to be a number or a string", 2)
end

function note.freq(n)
  if type(n) == "string" then
    local midi = nameToMidi(n)
    if not midi then
      error("Wrong input " .. tostring(n) .. BAD_NAME:format("freq"), 2)
    end
    return 2 ^ ((midi - 69) / 12) * 440
  elseif type(n) == "number" then
    return 2 ^ ((n - 69) / 12) * 440
  end
  error("Wrong input " .. tostring(n) ..
        " given to note.freq, needs to be a number or a string", 2)
end

function note.name(n)
  n = tonumber(n)
  if not n or n < MIDI_MIN or n > MIDI_MAX or n ~= math.floor(n) then
    error("Attempt to get a note for a non-exsisting MIDI code", 2)
  end
  return SHARP_NAME[n % 12] .. tostring(math.floor(n / 12) - 1)
end

function note.ticks(n)
  if type(n) ~= "number" then
    error("Wrong input " .. tostring(n) ..
          " given to note.ticks, needs to be a number", 2)
  end
  if n >= 0 and n <= 24 then return n + 34 end
  if n >= 34 and n <= 58 then return n - 34 end
  error("Wrong input " .. tostring(n) ..
        " given to note.ticks, needs to be a number [0-24 or 34-58]", 2)
end

function note.play(tone, duration)
  local freq = note.freq(tone)
  duration = tonumber(duration) or 0.1
  if duration ~= duration or duration <= 0 then return end
  if duration > MAX_PLAY_SECONDS then duration = MAX_PLAY_SECONDS end

  local okA, audio = pcall(require, "kernel.audio")
  if okA and audio and audio.isEnabled and not audio.isEnabled() then
    return
  end
  pcall(computer.beep, freq, duration)
end

return note

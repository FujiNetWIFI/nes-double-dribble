-- rig.lua -- one console of the two-player rig. Prints the STAT block every
-- STAT_EVERY seconds and once more as FINAL; snapshots every SNAP_EVERY.
--   RIG_SECS     run length (emulated seconds)
--   M4_AT        if set: at this many seconds after the match starts, poke
--                M4_ADDR := M4_VAL (a desync, for make m4)
--   SCREEN_TEXT  1 = print nametable 0 as text at the end (our UI screens)
local secs = tonumber(os.getenv("RIG_SECS") or "90")
local every = tonumber(os.getenv("STAT_EVERY") or "10")
local snap = tonumber(os.getenv("SNAP_EVERY") or "0")
local m4_at = tonumber(os.getenv("M4_AT") or "-1")
local m4_addr = tonumber(os.getenv("M4_ADDR") or "0x0320")
local m4_val = tonumber(os.getenv("M4_VAL") or "0x55")
local text = os.getenv("SCREEN_TEXT") == "1"
local prog = manager.machine.devices[":maincpu"].spaces["program"]
local ppu = manager.machine.devices[":ppu"].spaces["videoram"]
local NAMES = { "ACTIVE", "ROLE", "DROPPED", "WHY", "PSCR", "TLO", "THI", "SLIP",
  "REJ", "TMO", "ERR", "HOLD", "PEND", "LEAD", "STL", "RSY", "HLD", "GATE",
  "WAITED", "DELAY", "WMLO", "WMHI", "CRCLO", "CRCHI", "MIS", "MODE", "SES",
  "POLL", "LOCIN" }
local frame, started, poked = 0, nil, false
local snap_ticks = tonumber(os.getenv("SNAP_TICKS") or "0")
local last_bucket = 0

local function stat(tag)
  local t = {}
  for i, n in ipairs(NAMES) do
    t[#t + 1] = string.format("%s=%02X", n, prog:readv_u8(0x6300 + i - 1))
  end
  local tick = prog:readv_u8(0x6305) + 256 * prog:readv_u8(0x6306)
  print(string.format("%s t=%.1f tick=%d %s", tag, manager.machine.time:as_double(),
    tick, table.concat(t, " ")))
end

local function screen()
  for r = 0, 29 do
    local row = {}
    for c = 0, 31 do
      local v = ppu:readv_u8(0x2000 + r * 32 + c)
      row[#row + 1] = (v >= 0x20 and v < 0x7F) and string.char(v) or " "
    end
    local s = table.concat(row):gsub("%s+$", "")
    if #s > 0 then print(string.format("SCR %2d %s", r, s)) end
  end
end

_G.__rig = emu.add_machine_frame_notifier(function()
  frame = frame + 1
  if not started and prog:readv_u8(0x6319) == 1 then
    started = frame
    print(string.format("MATCH t=%.1f", manager.machine.time:as_double()))
  end
  if started and m4_at >= 0 and not poked and frame - started >= m4_at * 60 then
    poked = true
    prog:write_u8(m4_addr, m4_val)
    print(string.format("POKE $%04X := $%02X at tick %d", m4_addr, m4_val,
      prog:readv_u8(0x6305) + 256 * prog:readv_u8(0x6306)))
  end
  if snap_ticks > 0 and started then
    local tick = prog:readv_u8(0x6305) + 256 * prog:readv_u8(0x6306)
    local b = tick // snap_ticks
    if b > last_bucket then
      last_bucket = b
      -- the frame on screen now was drawn from tick b*snap_ticks's state on
      -- both consoles, give or take a stall; named so pairs line up
      manager.machine.screens[":screen"]:snapshot(string.format("tick%05d.png", b * snap_ticks))
    end
  end
  if snap > 0 and frame % (snap * 60) == 0 then manager.machine.screens[":screen"]:snapshot() end
  if every > 0 and frame % (every * 60) == 0 then stat("STAT") end
  if frame >= secs * 60 then
    manager.machine.screens[":screen"]:snapshot()
    stat("FINAL")
    if text then screen() end
    manager.machine:exit()
  end
end)

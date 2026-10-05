-- play.lua -- headless run: optional Lua-side pad script + fuzz, snapshots,
-- and a dump of the netcode STAT block ($6300) at the end.
--   PLAY_SECS   seconds to run (60)
--   SNAP_EVERY  seconds between snapshots (0 = only at the end)
--   LUA_PADS    1 = drive the pads from here (title: Select, Start; then
--               fuzz both pads, Start/Select masked)
--   STAT_EVERY  seconds between STAT prints (0 = only at the end)
local P = dofile(os.getenv("DD_EMU") .. "/pads.lua")
local secs = tonumber(os.getenv("PLAY_SECS") or "60")
local snap = tonumber(os.getenv("SNAP_EVERY") or "0")
local pads = os.getenv("LUA_PADS") == "1"
local stat_every = tonumber(os.getenv("STAT_EVERY") or "0")
local cpu = manager.machine.devices[":maincpu"]
local prog = cpu.spaces["program"]
local frame = 0
local r1, r2 = P.rng(0x1234), P.rng(0x5678)
local NAMES = { "ACTIVE", "ROLE", "DROPPED", "WHY", "PSCR", "TLO", "THI", "SLIP",
  "REJ", "TMO", "ERR", "HOLD", "PEND", "LEAD", "STL", "RSY", "HLD", "GATE",
  "WAITED", "DELAY", "WMLO", "WMHI", "CRCLO", "CRCHI", "MIS", "MODE", "SES",
  "POLL", "LOCIN" }

local function stat()
  local t = {}
  for i, n in ipairs(NAMES) do
    t[#t + 1] = string.format("%s=%02X", n, prog:readv_u8(0x6300 + i - 1))
  end
  local tick = prog:readv_u8(0x6305) + 256 * prog:readv_u8(0x6306)
  print(string.format("t=%.1f tick=%d %s", manager.machine.time:as_double(), tick, table.concat(t, " ")))
end

_G.__play = emu.add_machine_frame_notifier(function()
  frame = frame + 1
  if pads then
    if frame < 150 then P.set(1, 0); P.set(2, 0)
    elseif frame < 156 then P.set(1, 0x20)
    elseif frame < 190 then P.set(1, 0)
    elseif frame < 196 then P.set(1, 0x10)
    elseif frame < 256 then P.set(1, 0)
    elseif frame % 8 == 0 then P.set(1, r1() & 0xCF); P.set(2, r2() & 0xCF) end
  end
  if snap > 0 and frame % (snap * 60) == 0 then manager.machine.screens[":screen"]:snapshot() end
  if stat_every > 0 and frame % (stat_every * 60) == 0 then stat() end
  if frame >= secs * 60 then
    manager.machine.screens[":screen"]:snapshot()
    stat()
    manager.machine:exit()
  end
end)

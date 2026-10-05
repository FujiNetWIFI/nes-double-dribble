-- modes.lua -- log transitions of the game mode ($18) and its sub-state
-- ($2A), with how long each lasted; LUA_PADS-style fuzz. For finding a
-- quiet moment (a dead ball) to push a resync at.
local P = dofile(os.getenv("DD_EMU") .. "/pads.lua")
local prog = manager.machine.devices[":maincpu"].spaces["program"]
local secs = tonumber(os.getenv("PLAY_SECS") or "240")
local frame, last, since = 0, nil, 0
local r1, r2 = P.rng(0x1234), P.rng(0x5678)
_G.__m = emu.add_machine_frame_notifier(function()
  frame = frame + 1
  if frame < 150 then P.set(1, 0)
  elseif frame < 156 then P.set(1, 0x20)
  elseif frame < 190 then P.set(1, 0)
  elseif frame < 196 then P.set(1, 0x10)
  elseif frame % 8 == 0 then P.set(1, r1() & 0xDF); P.set(2, r2() & 0xCF) end
  local k = string.format("%02X/%02X", prog:readv_u8(0x18), prog:readv_u8(0x2A))
  if k ~= last then
    if last then print(string.format("f=%6d %s lasted %d", frame, last, frame - since)) end
    last, since = k, frame
  end
  if frame >= secs * 60 then manager.machine:exit() end
end)

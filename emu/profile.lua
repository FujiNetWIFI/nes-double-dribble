-- profile.lua -- RAM access map by writer/reader (bank:pc), lag-path count,
-- and reads of the fixed-bank bytes we want to reuse. Gets into a 2P game
-- and fuzzes both pads. Output: build/profile.txt (W/R lines).
local P = dofile(os.getenv("DD_EMU") .. "/pads.lua")
local secs = tonumber(os.getenv("PROF_SECS") or "90")
local cpu = manager.machine.devices[":maincpu"]
local prog = cpu.spaces["program"]
local W, R, F = {}, {}, {}
local lag, nmis, frame = 0, 0, 0
local r1, r2 = P.rng(0x1234), P.rng(0x5678)

local function who()
  local p = cpu.state["PC"].value
  local b = (p >= 0xC000) and 7 or prog:readv_u8(0x8000)
  return b * 0x10000 + p
end
local in_snd = false
_G.__se = prog:install_read_tap(0x807A, 0x807A, "pse", function(off)
  if prog:readv_u8(0x8000) == 1 and cpu.state["PC"].value == 0x807A then in_snd = true end
end)
_G.__sx = prog:install_read_tap(0xC072, 0xC072, "psx", function(off)
  if cpu.state["PC"].value == 0xC072 then in_snd = false end
end)
_G.__sy = prog:install_read_tap(0xC0AE, 0xC0AE, "psy", function(off)
  if cpu.state["PC"].value == 0xC0AE then in_snd = false end
end)
local function note(t, off)
  local e = t[off]
  if not e then e = {}; t[off] = e end
  local k = who()
  if in_snd then k = k | 0x800000 end
  e[k] = (e[k] or 0) + 1
end

_G.__wt = prog:install_write_tap(0x0000, 0x07FF, "pw", function(off) note(W, off) end)
_G.__rt = prog:install_read_tap(0x0000, 0x07FF, "pr", function(off, data)
  note(R, off)
  if off == 0x1B then
    local p = cpu.state["PC"].value
    if p >= 0xC03F and p <= 0xC043 then
      nmis = nmis + 1
      if data ~= 0 then lag = lag + 1 end
    end
  end
end)
_G.__ft = prog:install_read_tap(0xFFC0, 0xFFF9, "pf", function(off) note(F, off) end)

local function dump(tag, t, lo, hi)
  for a = lo, hi do
    local e = t[a]
    if e then
      local ks = {}
      for k, c in pairs(e) do ks[#ks + 1] = string.format("%s%d:%04X", (k & 0x800000) ~= 0 and "S" or "", (k >> 16) & 0xF, k & 0xFFFF) end
      table.sort(ks)
      print(string.format("%s %04X %s", tag, a, table.concat(ks, " ")))
    end
  end
end

_G.__f = emu.add_machine_frame_notifier(function()
  frame = frame + 1
  if frame < 120 then P.set(1, 0); P.set(2, 0)
  elseif frame < 126 then P.set(1, 0x20)
  elseif frame < 140 then P.set(1, 0)
  elseif frame < 146 then P.set(1, 0x10)
  elseif frame < 400 then P.set(1, 0)
  elseif frame % 8 == 0 then
    P.set(1, r1() & 0xCF); P.set(2, r2() & 0xCF)
  end
  if frame >= secs * 60 then
    print(string.format("NMI %d  lag %d", nmis, lag))
    dump("W", W, 0, 0x7FF); dump("R", R, 0, 0x7FF); dump("F", F, 0xFFC0, 0xFFF9)
    manager.machine:exit()
  end
end)

# Notes: how Double Dribble was made deterministic

Everything here was measured with `emu/profile.lua`, a MAME Lua RAM-access
map tagged by bank:PC, during 150 s of title, menus and fuzzed 2P play. It was
checked against the disassembly with `tools/dis6502.py`. None of it is
assumed.

## The ROM

- **Format:** NES 2.0, mapper 2 (UNROM, submapper 2: AND bus conflicts),
  8 × 16K PRG, 8K CHR-RAM, vertical mirroring. PRG CRC32 is `437E7B69`.
- **Vectors:** RESET is `$C001`, NMI `$C036`, and IRQ `$C08F` (a bare RTI).
- **Banks:** each bank stores its own number at `$8000`, and the code reads
  it back to save and restore the mapped bank. The bus-conflict table is
  `$FFD0`: `00..07`. The game never selects bank 7 (no read of `$FFD7` in
  the profile).
- **Fixed-bank free space:**
  - `$FFD8-$FFDF` holds `$FF`.
  - `$FFE0-$FFEF` is the internal title ("DOUBLE DRIBBLE"), never read.
  - `$FFF0-$FFF9` is the Nintendo header (checksum etc.), never read; the
    `"FUJI"` claim goes here.
  - `$FFC0` *is* read once per frame (something in the sound path), so it is
    left alone.

## Where the game runs

All of the simulation runs inside the NMI. The RESET code ends in a main loop
at `$C02B` that only does `$63 += $1A + C; $63++`, as fast as the CPU allows.

The NMI normal path, taken when `$1B` is 0:

1. Rendering off, OAM DMA, flush the `$0700` VRAM list.
2. `$D371`: the status-bar scroll, sprite 0, **the pad read `$C2E6`**, bank 2
   `$81C9` (sprite cycling), then **the sprite-0 split wait `$D39E`** (mode 5).
3. `INC $1B`.
4. Bank 1 `$807A` (the sound engine) and bank 2 `$8154` (sprites).
5. Bank 0 **`$C187`: the game state machine** (`INC $1A`, dispatch on `$18`).
6. `$C77F` terminates the VRAM list, then `$1B` = 0.

The lag path, taken when `$1B` ≠ 0 because the last NMI is still running,
runs `$D371` (no pad read) and the sound engine unless `$1B` bit 7 is set.
Stock play takes it about 12 times in 9,000 NMIs.

## Determinism traps, in the order they bit

1. **The RNG.** `$63` is churned by the main loop roughly 1,100 times per
   frame, so the value the game reads depends on how long the previous NMI
   took. That is fine on one console and fatal for two. In lockstep the main
   loop just spins (`W_IDLE`), and `$63` is stepped 8 times per tick from a
   16-bit Galois LFSR seeded by the server's START seed. Local play keeps the
   stock loop.
2. **Lag-path sound.** The sound engine ticks on lag frames as well, and in
   lockstep the lag frames differ between consoles because the stall spins
   inside the NMI. The engine's RAM is `$70-$D7`. The only things that read
   it are the engine itself (inside the `$807A` call, bracketed by opcode-fetch
   taps) and the sound API at `$CC00-$CDFF`, which writes only sound RAM.
   `W_LAG` still skips the lag-path sound tick in lockstep, so sound advances
   exactly once per sim tick and sound RAM can never diverge.
3. **Re-entry through `$1B`.** The first hook replaced the pad read and
   cleared `$1B` on return, as stock does. Between there and `INC $1B` sits
   the sprite-0 split wait. A tick that stalled got there after sprite 0 had
   hit, waited out the next vblank, and that NMI found `$1B` = 0 and
   re-entered the normal path. The symptom was the stack pointer sinking a
   byte per frame (`make det` B stuck at tick 2784, its first injected stall).
4. **Split-wait livelock.** Even with `$1B` held, an outer split wait that
   starts after the hit never sees the flag edges: every nested lag NMI does
   its own split and consumes them. So the tick hook moved to `JSR $C187` at
   `$C07F`. By then the split is done, `$1B` is already 1, and the only
   readers of the pad bytes `$F5-$F8` are under `$C187` (profile). The `$D37B`
   pad read becomes a no-op in lockstep. `$04`, `$05` and `$07`, which are
   scratch to the sprite code and the logic, are saved and restored around
   our own pad reads and the stock edge code `$C2FA`.

## Free RAM

- Zero page `$F0-$F4` and `$F9-$FB` are never written by the game and lie
  outside the `$00-$EF` block its init clears.
- `$0100-$012F` and much of `$0130-$01B0` are written only by the init
  clear, but the netcode does not need them.
- Everything else lives in the cart's WRAM, which the NES 2.0 header requests
  (byte 10 = `$07`, 8K). The fn-nes cart's `nesmap.c` serves it for any
  mapper that asks.

## The checksum

The CRC covers zero page minus scratch `$00-$07`, `$1B`, the bank saves
`$3C/$3D`, the sound engine `$70-$D7`, our bytes and the PPU shadows
`$FE/$FF`. It also covers the object tables `$0300-$06FF` and the LFSR. OAM
(`$0200`) and the VRAM list (`$0700`) are display and are left out.
`make det` compares this checksum every tick over 1,000-tick windows.

## Timeouts

Timeouts count frames (nested lag NMIs, `NMI_SEEN`), never pump rounds.
Under MAME the FujiNet cart device answers a mailbox transaction in zero
emulated time, so a pump-round budget would expire in milliseconds. For the
same reason the two-console rigs run MAME throttled (`THROTTLE=1`).

## The resync image

The image is 3,874 bytes:

- zero page;
- `$0200-$07FF`;
- both nametables (`$2000-$27FF`);
- the palette;
- the LFSR.

The host snapshots it at the end of a tick, with NMI and rendering off for
the VRAM reads, then pushes it in 96-byte STATE chunks. The guest stages it
in WRAM and applies it atomically on END, from inside its tick hook. Applying
skips the stack page, the scratch bytes, `$1B`, the bank saves and our zero
page.

The host's queued `$0700` updates travel in the image, and the guest's next
NMI flushes them, so the nametables end up the same.

CHR-RAM is not in the image (8K would not fit beside everything else). A
desync inside one scene leaves it the same on both consoles.

## A quiet moment for the push

`emu/modes.lua` logs `$18` and `$2A` transitions. On the court (`$18` = 5),
`$2A` steps `$01..$08` through the setup and the tip-off, sits at `$0E` for
live play, and goes `$0C`/`$0D` at the period break. `RS_QUIET` therefore
treats anything but `$0E` as dead ball. Inside live play a push waits for
the `RS_PEND_MAX` cap of 240 ticks.

## Rig lessons

- Headless MAME and fujinet-pc ignore SIGTERM. Survivors held the rig's
  ports, and the next run's relay failed to bind while the consoles talked
  to the stale one. `run_rig.sh` now SIGKILLs everything and refuses to start
  on a busy port.
- Anything exported to `run_rig.sh` reaches both consoles. A test switch for
  one console only (`M4_AT`) has to be removed from the other's environment
  (`env -u`), or both consoles get the same poke and nothing desyncs.

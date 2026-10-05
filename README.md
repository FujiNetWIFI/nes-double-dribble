# Double Dribble (NES) — FujiNet Netplay

Two-player Konami Double Dribble (1987) head to head over the network. Each
player sits at their own NES with the FujiNet cartridge, and a small relay
server matches them by username. Behaviour follows the FujiNet netplay ports
on other platforms (`~/Workspace/intv-baseball-experiment` and its siblings):

- your name comes from the Lobby username appkey;
- you pick an opponent from a lobby list, and the waiting player becomes host;
- input is exchanged in delay-based lockstep;
- a CRC check every 64 ticks detects desyncs, and the host repairs one by
  pushing its state;
- when the opponent goes, an "OPPONENT LEFT" or "CONNECTION LOST" screen
  shows the field-diagnostic counters.

**Architecture.** Both consoles run the full, lightly patched original game.
A sim tick is one pass of the NMI's normal path, because Double Dribble runs
its whole simulation inside the NMI. Tick-stamped pad bytes travel over a
persistent `N:TCP://` connection through the relay, and both sims apply both
players' inputs at the same tick. Local input is delayed by `d` ticks (3 by
default, set by the server).

When the network is late, the stall spins inside the NMI with the game's
"busy" flag held. The NMIs that fire meanwhile take the game's own lag path,
so the display stays alive while the sim and the sound engine stand still.
The netcode lives in a new PRG bank: the ROM grows from UNROM to UOROM. Its
state lives in the cart's 8K WRAM, and nine declared patch sites in the fixed
bank hook it in. Details and the measurements behind each decision are in
`spikes/NOTES.md`.

## Layout

| Path | Contents |
|---|---|
| `rom/` | The original `double_dribble.nes` (UNROM, 128K, CHR-RAM) |
| `src/bank8.s` | The netcode bank: entry, WRAM trampolines, boot |
| `src/netcode/mailbox.s` | FujiNet cart mailbox, N: device and appkey calls |
| `src/netcode/session.s` | Name, server, lobby, START, stream pump and frame parser |
| `src/netcode/lockstep.s` | Tick hooks, gate and stall, feed, RNG, CRC, peer-left screen |
| `src/netcode/resync.s` | CRC records, desync detection, state push and apply |
| `src/ui/text.s` | Text screens; the font is shared with the fn-nes bring-up |
| `tools/patches.py` | Every changed fixed-bank byte, with its original bytes |
| `tools/build_rom.py` | Splices bank 8 in, applies the patches, writes the NES 2.0 header |
| `tools/check_patch.py` | Fails on any undeclared change |
| `tools/checkrom.py` | Bans RMW instructions aimed at the mailbox |
| `tools/dis6502.py` | Small disassembler and xref tool for the ROM |
| `server/dd_relay_server.py` | Matchmaking and relay, the Baseball protocol unchanged |
| `emu/` | MAME Lua: `profile` (RAM access map), `modes`, `play`, `det`, `rig`, `lobby`; `run.sh` launches MAME |
| `test/` | `run_det.sh`, `run_rig.sh`, `rig_verdict.py`, `run_lobby.sh`, `lobby_idlers.py` |

## Build and verify (headless)

Requirements: cc65 (`ca65`, `ld65`), Python 3, the patched MAME in
`~/Workspace/mame` (fn-nes `pico/nes/emu/apply.sh`), and
`~/Workspace/fujinet-pc-rs232/build/dist` for the rigs.

```sh
make verify-org   # split + rejoin of the original ROM is byte-identical
make hook         # HOOK build (all hooks in, nothing armed) + patch audit
make det          # determinism A/B: in-console fuzz, 9-frame stall every 64
                  # ticks in B, per-tick sim checksums must match (PASS)
make rig          # 2x fujinet-pc + relay + 2x MAME, auto-matched, fuzz,
                  # CRC cross-check, zero diag counters (RIG PASS)
make m4           # desync injection -> detect -> push -> recover (M4 PASS)
make peerleft     # opponent leaves: clean (OPPONENT LEFT) and timeout
                  # (CONNECTION LOST); both must PASS
make lobby        # the session screens as text + snapshots, against idle
                  # players parked in the relay (after one `make rig`)
python3 tools/test_lobby_pub.py   # Lobby registration contract
```

## Play

Two consoles side by side on one machine, everything set up for you:

```sh
make play          # or tools/play_local.sh; P1_NAME=.. P2_NAME=.. DELAY=..
```

This starts two isolated fujinet-pc copies (`build/play/`), each with its
own username appkey and the Lobby server-URL appkey, plus the relay on :9700
and two MAME windows. Challenge one player from the other's lobby. Each
console uses its own controller 1, and keys go to the focused window.
Closing either window or pressing Ctrl-C stops everything.

Against a real server:

```sh
make SRV_HOST=<server> SRV_PORT=9700   # build/dd_net.nes
python3 server/dd_relay_server.py --port 9700
emu/run.sh build/dd_net.nes            # MAME window, FujiNet cart slot
```

The netplay screens work like this:

- **Name:** taken from the FujiNet Lobby username appkey (creator 1 / app 1 /
  key 0), upper-cased, falling back to `GUESTnn`.
- **Server:** taken from the Lobby's handoff appkey (key `GAME_APPKEY`, 40)
  when the game was booted from the NES Lobby, otherwise the endpoint baked
  in at build time.
- **Lobby:** Up and Down move the cursor, A or Start challenges, and Select
  plays locally instead.
- **Roles:** the waiting player becomes host, which makes them 1UP. Both
  players use controller 1 on their own console.
- **Menus:** the title and option menus run in lockstep, exactly as on a
  couch, so 1UP drives them; the game already lets 2UP's Start and Select
  count too.

With no FujiNet or no server, the stock game runs locally.

## Status

Verified in emulation (MAME with the FujiNet cart device, two fujinet-pc
instances). The cartridge hardware does not exist yet.

- `det` PASS at 3,000, 7,000, 8,000 and 12,000 ticks, through the title,
  menus, tip-off and live play.
- `rig` PASS:
  - 96 CRC pairs with no mismatches, and every diagnostic counter at zero;
  - the two consoles render pixel-identical frames at the same ticks;
  - console 1 connects only through the Lobby's server-URL appkey (its
    baked-in endpoint is a dead port), and its name comes from the username
    appkey.
- `m4` PASS:
  - a poked byte is detected at the next CRC;
  - the host pushes the 3,874-byte image, at once when the ball is dead
    (`RS_QUIET`: the court's phase byte `$2A` is not `$0E`), otherwise after
    a 4 s cap;
  - both sims rebase and agree from then on, and the frames are
    pixel-identical after the push too.
- `peerleft` PASS for both a clean leave and a timeout.
- `lobby`: the name, list, IN GAME rows, cursor, challenge, matched screen
  and handover into the game all checked on screen.

Open items:

- `d` needs tuning on real hardware (the default is 3, i.e. 50 ms).
- There is no PAL guard yet.
- CHR-RAM is not in the resync image.
- Port 9700 and appkey 40 are proposals and must be confirmed before a
  production `server/run_production.sh`.

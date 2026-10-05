"""patches.py -- every byte the build changes in Double Dribble's fixed bank.

Each entry: console address, the ORIGINAL bytes (checked before patching, so
a wrong ROM or a moved routine fails the build), the replacement (a list of
ints and symbol names; a symbol expands to its 16-bit little-endian value
from the bank-8 label file), and why. check_patch.py fails the build on any
difference between the original and patched fixed bank not listed here.
"""

PATCHES = [
    (0xC025, [0x20, 0xB9, 0xC0], [0x20, 0xE0, 0xFF],
     "RESET: JSR $C0B9 (NMI on) -> JSR boot stub; NET_BOOT tail-calls $C0B9"),
    (0xFFE0, [0x00, 0x00, 0x44, 0x4F, 0x55, 0x42, 0x4C, 0x45],
     [0xA9, 0x08, 0x8D, 0xD8, 0xFF, 0x4C, 'NET_BOOT'],
     "boot stub over the unused title text: LDA #8 / STA $FFD8 / JMP NET_BOOT"),
    (0xFFD8, [0xFF] * 8, list(range(8, 16)),
     "bus-conflict bank table, extended from 8 to 16 entries"),
    (0xFFF0, [0xC8, 0x0F, 0x00, 0x00], list(b"FUJI"),
     "the FujiNet claim: keeps the cart mailbox alive (header checksum: unused)"),
    (0xC02B, [0xA5, 0x63, 0x65], [0x4C, 'W_IDLE'],
     "main loop: the timing-dependent $63 churn -> W_IDLE"),
    (0xD37B, [0x20, 0xE6, 0xC2], [0x20, 'W_PAD'],
     "NMI pad read: JSR $C2E6 -> JSR W_PAD (in lockstep: nothing; LS_TICK feeds)"),
    (0xC07F, [0x20, 0x87, 0xC1], [0x20, 'W_TICK'],
     "NMI tick start: JSR $C187 (game logic) -> JSR W_TICK (gate, feed, then $C187)"),
    (0xC082, [0x20, 0x7F, 0xC7], [0x20, 'W_POST'],
     "NMI tick end: JSR $C77F -> JSR W_POST (which calls $C77F first)"),
    (0xC0A2, [0xA5, 0x1B, 0x30, 0x08], [0x4C, 'W_LAG', 0xEA],
     "lag path: LDA $1B / BMI $C0AE -> JMP W_LAG (no sound tick in lockstep)"),
]

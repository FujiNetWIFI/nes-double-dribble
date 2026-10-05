; defs.inc -- equates shared by every netcode module.
;
; Three address spaces meet here: the game's own RAM (measured, not assumed:
; emu/profile.lua), the FujiNet cartridge mailbox at $5000 (mirrored from
; fn-nes/pico/nes/firmware/include/fuji_mailbox.h), and the cart's WRAM at
; $6000 that the NES 2.0 header asks for (all netcode state lives there).

; ---------------------------------------------------------------- PPU / APU
PPU_CTRL        = $2000
PPU_MASK        = $2001
PPU_STATUS      = $2002
PPU_SCROLL      = $2005
PPU_ADDR        = $2006
PPU_DATA        = $2007

; ---------------------------------------------------------------- mailbox
; THE ONE RULE: only STA/STX/STY to $5500-$57FF, never an RMW instruction.
; tools/checkrom.py audits it.
FN_RPLY         = $5000         ; 1K reply window
FN_ACKS         = $5400         ; echoes SEQ when the reply is ready
FN_ERR          = $5402
FN_RCMD         = $5403         ; $06 ACK / $15 NAK
FN_RXLO         = $5404
FN_RXHI         = $5405
FN_MAG0         = $5409         ; 'F'
FN_MAG1         = $540A         ; 'N'
FN_RSEL         = $5500         ; STA $5500+n: register n = A
FN_TX           = $5700         ; a write anywhere appends to the TX stream
FR_DEV          = $00
FR_CMD          = $01
FR_NPAR         = $02
FR_DRST         = $05
FR_SEQ          = $10

FNDEV_FUJI      = $70
FNDEV_N1        = $71
NETCMD_OPEN     = $4F
NETCMD_CLOSE    = $43
NETCMD_READ     = $52
NETCMD_WRITE    = $57
NETCMD_STATUS   = $53
OPEN_MODE_RW    = 12
CMD_OPEN_APPKEY = $DC
CMD_CLOSE_APPKEY = $DB
CMD_READ_APPKEY = $DD

; Mailbox wait budgets, in ~0.55 s units (one unit = 256 x 256 polls).
MB_TMO_FAST     = 12            ; ordinary transaction: past the cart's 5 s
MB_TMO_OPEN     = 180           ; N: OPEN / CLOSE: the cart allows 90 s

; ---------------------------------------------------------------- wire
; Frame type ids -- must match server/dd_relay_server.py.
FT_HELLO        = $01
FT_LIST         = $02
FT_LOBBY        = $03
FT_JOIN         = $04
FT_START        = $05
FT_INPUT        = $06
FT_CRC          = $07
FT_STATE        = $08
FT_RESYNC       = $09
FT_BYE          = $0A
FT_PEER_LEFT    = $0B
FT_PING         = $0C
FT_PONG         = $0D
PROTO_VER       = 1

; ---------------------------------------------------------------- the game
; Measured with emu/profile.lua against the stock ROM; see spikes/NOTES.md.
G_PAD1          = $04           ; raw P1 (the AND of two strobed reads)
G_PAD2          = $05           ; raw P2
G_MODE          = $18           ; game mode, dispatched by $C187
G_FRAME         = $1A           ; frame counter, INC'd at $C187
G_BUSY          = $1B           ; NMI busy flag: nonzero = lag path
G_RNG           = $63           ; the free-running random byte
G_PPUMASK       = $FE           ; shadow of $2001
G_PPUCTRL       = $FF           ; shadow of $2000

G_READPADS      = $C314         ; strobe + shift both ports into $04/$05
G_PADTAIL       = $C2FA         ; the rest of $C2E6: edges into $F5-$F8 (X=0)
G_READ2         = $C2E6         ; stock: read twice, AND, derive edges
G_LOGIC         = $C187         ; the game's state machine: the sim proper
G_VBUF_END      = $C77F         ; terminate the $0700 VRAM update list
G_VBUF_FLUSH    = $CB63         ; NMI: flush the $0700 list to the PPU
G_NMI_ON        = $C0B9         ; APU init + PPUCTRL=$B0 (NMI on)
G_LAG_SND       = $C0A6         ; lag path: bank 1, sound tick
G_LAG_NOSND     = $C0AE         ; lag path: skip the sound tick
G_BANKTBL       = $FFD0         ; bus-conflict table, extended to 16 by us

NET_BANK        = 8             ; this file's bank

; ---------------------------------------------------------------- zero page
; $F0-$F4 and $F9-$FB: never written by the game (profile.lua, 150 s of
; title + 2P play), and outside the $00-$EF block its init clears.
ZP_PTR          = $F0           ; 2 bytes
ZP_PTR2         = $F2           ; 2 bytes
ZP_TMP          = $F4
ZP_T1           = $F9
ZP_T2           = $FA
ZP_T3           = $FB

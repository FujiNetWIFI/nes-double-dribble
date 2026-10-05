; bank8.s -- the netcode bank. Double Dribble is UNROM (mapper 2, 8 x 16K);
; the build grows it to UOROM (16 x 16K), moves the fixed bank to slot 15 and
; puts everything here in slot 8. The game never selects past bank 6.
;
; How control gets here (all patch sites: tools/patches.py):
;   RESET  $C025  JSR $C0B9  -> JSR $FFE0, a fixed-bank stub that maps this
;                               bank and jumps to NET_BOOT ($8003)
;   NMI    $D37B  JSR $C2E6  -> JSR W_PAD   (the pad read; lockstep: none)
;          $C07F  JSR $C187  -> JSR W_TICK  (tick start: gate, feed, logic)
;          $C082  JSR $C77F  -> JSR W_POST  (end of the tick)
;          $C0A2  LDA $1B/BMI -> JMP W_LAG  (lag path's sound gate)
;   main   $C02B  RNG churn  -> JMP W_IDLE
; The W_* trampolines live in WRAM ($7F00): the NMI runs with any bank
; mapped and the fixed bank has no room, but WRAM is always there.
;
; Build kinds (ca65 -D BUILD_KIND=n):
;   0 HOOK   every hook installed, nothing armed: must play exactly as stock
;   1 NET    the real thing: session, lobby, lockstep
;   2 SOLO   lockstep with no network: the "remote" side is controller 2
;            (or fuzz), delayed like a peer's input -- run-lag and det
; Test switches: FUZZ (inputs from per-side LFSRs), STALL_N (inject a
; stall of N frames every 64 ticks), TRACE (per-tick checksum ring),
; AUTO_JOIN (rig consoles challenge the first idle lobby entry),
; SOLO_DELAY (the d of a SOLO build).

        .include "defs.inc"

.ifndef BUILD_KIND
BUILD_KIND = 1
.endif
.ifndef FUZZ
FUZZ = 0
.endif
.ifndef STALL_N
STALL_N = 0
.endif
.ifndef TRACE
TRACE = 0
.endif
.ifndef AUTO_JOIN
AUTO_JOIN = 0
.endif
.ifndef SOLO_DELAY
SOLO_DELAY = 3
.endif

        .import __TRAMP_LOAD__, __TRAMP_RUN__, __TRAMP_SIZE__

        .include "netcode/image.inc"
        .include "vars.inc"

; ---------------------------------------------------------------- bank head
        .segment "B8HEAD"
        .byte   NET_BANK        ; $8000: every bank names itself here, and the
        .byte   $FF, $FF        ;   lag path reads it back to restore the bank
        ; $8003 -- entered from the fixed-bank stub at $FFE0 by a JMP, in
        ; place of the game's JSR $C0B9, so the return address on the stack
        ; is $C028 and we leave with a tail call to $C0B9.
NET_BOOT:
        jmp     boot

; ---------------------------------------------------------------- WRAM
        .segment "TRAMP"
; Copied to $7F00 at every boot. Each hook preserves what the instruction it
; replaced preserved -- nothing, in every case, as the disassembly shows.

; W_PAD -- replaces JSR $C2E6 (the pad read) in $D371. In lockstep the pads
; are read and fed by LS_TICK instead, later in the same NMI.
W_PAD:
        lda     NET_MODE
        bne     @net
        jmp     G_READ2         ; local: the stock pad read, untouched
@net:   rts

; W_TICK -- tick start. Replaces JSR $C187 (the game's state machine) at
; $C07F, with bank 0 mapped and $1B = 1. Why here and not at the pad read:
; between the two sits the sprite-0 split wait at $D39E. Stock, nothing
; slow ever runs before it; a tick that stalls there arrives after sprite 0
; has hit, and the lag NMIs that keep the display alive meanwhile each do
; their own split and swallow every flag edge it waits for -- a livelock.
; Here the split is done, and the only readers of the pad bytes ($F5-$F8)
; are the game logic $C187 is about to run (profile.lua).
W_TICK:
        lda     NET_MODE
        beq     @go
        lda     $8000
        pha
        lda     #NET_BANK
        sta     G_BANKTBL+NET_BANK
        jsr     LS_TICK
        pla
        tay
        lda     G_BANKTBL,y
        sta     G_BANKTBL,y
@go:    jmp     G_LOGIC

; W_POST -- end of the tick. Replaces JSR $C77F at $C082.
W_POST:
        jsr     G_VBUF_END
        lda     NET_MODE
        bne     @net
        rts
@net:   lda     $8000
        pha
        lda     #NET_BANK
        sta     G_BANKTBL+NET_BANK
        jsr     LS_POST
        pla
        tay
        lda     G_BANKTBL,y
        sta     G_BANKTBL,y
        rts

; W_LAG -- the lag path's "tick the sound engine?" test (LDA $1B / BMI).
; A lag frame is an NMI that found the last one still running. Stock, the
; sound engine runs on those too; in lockstep that would make sound state
; depend on CPU timing, which differs between the consoles (the stall spins
; INSIDE the NMI). The engine's RAM ($70-$D7) is read by nothing but itself
; and the sound API (profile.lua), but it is cheaper to keep it exact than
; to prove that forever: in lockstep the sound ticks once per sim tick,
; on the normal path only.
W_LAG:
        lda     NET_MODE
        bne     @net
        lda     G_BUSY
        bmi     @nosnd
        jmp     G_LAG_SND
@net:   inc     NMI_SEEN        ; the stall loops count frames off this
@nosnd: jmp     G_LAG_NOSND

; W_IDLE -- the main loop. Stock, it churns $63 as fast as the CPU allows
; between NMIs, so the value the game sees depends on how long the last NMI
; took: fine on one console, fatal for two. In lockstep $63 is stepped once
; per tick from a seeded LFSR instead (LS_TICK), and this just waits.
W_IDLE:
        lda     NET_MODE
        bne     @spin
        lda     G_RNG
        adc     G_FRAME
        sta     G_RNG
        inc     G_RNG
        jmp     W_IDLE
@spin:  jmp     @spin

; ---------------------------------------------------------------- boot
        .segment "CODE"

.proc boot
        ; the trampolines
        ldx     #0
:       lda     __TRAMP_LOAD__,x
        sta     __TRAMP_RUN__,x
        inx
        cpx     #<__TRAMP_SIZE__
        bne     :-
        ; WRAM survives a console reset; the netcode's state must not
        lda     #0
        tax
:       sta     $6300,x         ; STAT block
        inx
        bne     :-
        sta     NET_MODE
        sta     NMI_SEEN

.if ::BUILD_KIND = 1
        jsr     SES_MAIN        ; sets NET_MODE: 1 netplay, 0 local game
.elseif ::BUILD_KIND = 2
        jsr     LS_SOLO_INIT
        lda     #2
        sta     NET_MODE
.endif
        ; hand the machine back exactly as the game left it at $C025:
        ; NMI and rendering off, nothing of ours on screen, our scratch
        ; bytes back to the zero the game's own init gave them
        jsr     UI_OFF
        jsr     UI_WIPE
        lda     #0
        ldx     #7
:       sta     $00,x
        dex
        bpl     :-
        jmp     G_NMI_ON        ; returns to $C028
.endproc

        .include "ui/text.s"
        .include "netcode/mailbox.s"
        .include "netcode/session.s"
        .include "netcode/lockstep.s"
        .include "netcode/resync.s"

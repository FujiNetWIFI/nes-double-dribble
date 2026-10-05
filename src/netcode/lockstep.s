; lockstep.s -- delay-based input lockstep, hooked into Double Dribble's NMI.
;
; The sim clock is one pass through the NMI's normal path: the game's
; state machine ($C187) runs there and nowhere else. LS_TICK runs just
; before it (W_TICK, $C07F), LS_POST just after ($C082).
;
; Tick T:
;   LS_TICK  capture local pad -> LOC_RING[T+d], send INPUT(T+d)
;            gate: wait until the peer's watermark reaches T. The wait
;              spins RIGHT HERE, inside the NMI, with $1B nonzero (the INC
;              at $C068): the NMIs that fire meanwhile take the game's own
;              lag path, which keeps the display alive and (W_LAG) leaves
;              the sim alone.
;            feed $04/$05 by role, run the stock edge code ($C2FA) into
;              $F5-$F8, put the scratch back, step the RNG
;   LS_POST  pump, CRC every 64 ticks, T++, deferred resync
;
; Roles: host = the waiting player = 1UP: its local pad is P1 ($04).

LS_TIMEOUT      = $0258         ; gate frames (10 s) before the peer is lost
RS_HOLD_TMO     = $0384         ; hold frames (15 s) before giving up

; ---------------------------------------------------------------------------
; LS_START -- arm the engine at tick 0 (from START, or a SOLO boot).
.proc LS_START
        lda     #0
        tax
:       sta     LOC_RING,x
        sta     RMT_RING,x
        inx
        bne     :-
        sta     TICK_LO
        sta     TICK_HI
        sta     RMT_WM_HI
        sta     NET_DROPPED
        sta     PEER_SCR
        sta     RESYNC_HOLD
        sta     RS_PEND
        sta     LS_WAITC_LO
        sta     LS_WAITC_HI
        lda     NET_DELAY
        sec
        sbc     #1
        sta     RMT_WM_LO       ; ticks 0..d-1 are known: idle
        jsr     RS_CLR_CRC
        ; fuzz streams, per side, so a rig is reproducible
        lda     #$34
        ldx     #$12
        ldy     NET_ROLE
        beq     :+
        lda     #$78
        ldx     #$56
:       sta     FUZ_LO
        stx     FUZ_HI
        lda     #$78
        sta     FUZ2_LO
        lda     #$56
        sta     FUZ2_HI
        lda     #0
        sta     FUZ_CUR
        sta     FUZ_CUR+2
        rts
.endproc

; LS_SOLO_INIT -- SOLO builds: lockstep with no network. The "peer" is
; controller 2 (or a second fuzz stream), delayed like a real peer.
.proc LS_SOLO_INIT
        lda     #SOLO_DELAY
        sta     NET_DELAY
        lda     #0
        sta     NET_ROLE
        lda     #$E1
        sta     LFSR_LO
        lda     #$AC
        sta     LFSR_HI
        jsr     LS_START
        lda     #1
        sta     NET_ACTIVE
        rts
.endproc

; LS_IDLE_RMT -- peer gone: idle the remote ring, pin the watermark far
; ahead.
.proc LS_IDLE_RMT
        lda     #0
        tax
:       sta     RMT_RING,x
        inx
        bne     :-
        lda     TICK_LO
        sta     RMT_WM_LO
        lda     TICK_HI
        clc
        adc     #$40
        sta     RMT_WM_HI
        rts
.endproc

; ---------------------------------------------------------------------------
; LS_TICK -- tick start. Entered from W_TICK with this bank mapped, inside
; the NMI, $1B = 1.
.proc LS_TICK
        ; $04, $05 and $07 are scratch to the sprite code that ran before us
        ; and the game logic after; the pad reads below use them, so they
        ; go back exactly as found
        lda     G_PAD1
        sta     SAV_04
        lda     G_PAD2
        sta     SAV_05
        lda     $07
        sta     SAV_07
@top:   lda     NET_DROPPED
        beq     :+
        jmp     LS_GONE
:       lda     RESYNC_HOLD
        beq     @tick
        jsr     LS_HOLD
        jmp     @top
@tick:  ; ---- capture local input for T+d ------------------------------
        jsr     LS_LOCAL        ; A = ours, ZP_T2 = controller 2 (SOLO)
        sta     LOCAL_IN
        lda     TICK_LO
        clc
        adc     NET_DELAY
        sta     ZP_PTR2
        lda     TICK_HI
        adc     #0
        sta     ZP_PTR2+1
        ldx     ZP_PTR2
        lda     LOCAL_IN
        sta     LOC_RING,x
        lda     NET_MODE
        cmp     #2
        beq     @solo
        ; INPUT: [5][06][tick_lo][tick_hi][pad][0]
        lda     #5
        sta     TXBUF
        lda     #FT_INPUT
        sta     TXBUF+1
        lda     ZP_PTR2
        sta     TXBUF+2
        lda     ZP_PTR2+1
        sta     TXBUF+3
        lda     LOCAL_IN
        sta     TXBUF+4
        lda     #0
        sta     TXBUF+5
        ldx     #6
        jsr     NET_WRITE
        jmp     @gate
@solo:  jsr     LS_SOLO_RMT
        ldx     ZP_PTR2
        sta     RMT_RING,x
        lda     ZP_PTR2
        sta     RMT_WM_LO
        lda     ZP_PTR2+1
        sta     RMT_WM_HI
@gate:
.if ::STALL_N > 0
        ; test builds: a STALL_N-frame stall every 64 ticks, to prove the
        ; sim does not care how long a tick takes
        lda     TICK_LO
        and     #$3F
        cmp     #$20
        bne     @nost
        lda     NMI_SEEN
        clc
        adc     #STALL_N
        sta     STALL_CNT
:       lda     NMI_SEEN
        cmp     STALL_CNT
        bne     :-
@nost:
.endif
        lda     NMI_SEEN
        sta     LS_TMP
        lda     #0
        sta     LS_WAITC_LO
        sta     LS_WAITC_HI
@g:     ; WM - T >= 0 ?
        lda     RMT_WM_LO
        sec
        sbc     TICK_LO
        sta     ZP_T3
        lda     RMT_WM_HI
        sbc     TICK_HI
        bpl     @run
        ; ---- stall -------------------------------------------------------
        lda     #0
        sta     HUD_LEAD
        lda     HUD_STL
        cmp     #$FF
        beq     :+
        inc     HUD_STL
:       jsr     SES_PUMP
        lda     NET_DROPPED
        beq     :+
        jmp     LS_GONE
:       lda     RESYNC_HOLD     ; a BEGIN landed while we waited
        beq     :+
        jsr     LS_HOLD
        jmp     @top
:       lda     NMI_SEEN        ; count frames, not pumps: a pump can take
        cmp     LS_TMP          ;   no emulated time at all under MAME
        beq     @g
        sta     LS_TMP
        inc     LS_WAITC_LO
        bne     :+
        inc     LS_WAITC_HI
:       lda     LS_WAITC_HI
        cmp     #>LS_TIMEOUT
        bcc     @g
        lda     LS_WAITC_LO
        cmp     #<LS_TIMEOUT
        bcc     @g
        lda     #0
        sta     PEER_WHY        ; we timed out, no clean goodbye
        lda     #1
        sta     NET_DROPPED
        jmp     LS_GONE
@run:   ; slack, for the rigs: how many ticks of remote input in hand
        bne     @lead15
        lda     ZP_T3
        cmp     #16
        bcc     :+
@lead15:
        lda     #15
:       sta     HUD_LEAD
        ; ---- feed the pair by role ----------------------------------------
        ldx     TICK_LO
        lda     LOC_RING,x
        ldy     RMT_RING,x
        ldx     NET_ROLE
        bne     @guest
        sta     G_PAD1          ; host: we are P1
        sty     G_PAD2
        jmp     @fed
@guest: sty     G_PAD1
        sta     G_PAD2
@fed:   ldx     #0
        jsr     G_PADTAIL       ; the stock edge logic into $F5-$F8
        lda     SAV_04
        sta     G_PAD1
        lda     SAV_05
        sta     G_PAD2
        lda     SAV_07
        sta     $07
        jmp     LS_RNG
.endproc

; LS_HOLD -- resync hold: the sim stays frozen here, pumping, until the
; END frame rebases us (RESYNC_HOLD back to 0) or the peer is lost.
.proc LS_HOLD
        lda     NMI_SEEN
        sta     LS_TMP
        lda     #0
        sta     RS_TO_LO
        sta     RS_TO_HI
@l:     jsr     SES_PUMP
        lda     RESYNC_HOLD
        beq     @out
        lda     NET_DROPPED
        bne     @out
        lda     HUD_HLD
        cmp     #$FF
        beq     :+
        inc     HUD_HLD
:       lda     NMI_SEEN
        cmp     LS_TMP
        beq     @l
        sta     LS_TMP
        inc     RS_TO_LO
        bne     :+
        inc     RS_TO_HI
:       lda     RS_TO_HI
        cmp     #>RS_HOLD_TMO
        bcc     @l
        lda     RS_TO_LO
        cmp     #<RS_HOLD_TMO
        bcc     @l
        lda     #0
        sta     PEER_WHY
        sta     RESYNC_HOLD
        lda     #1
        sta     NET_DROPPED
@out:   rts
.endproc

; ---------------------------------------------------------------------------
; LS_POST -- tick end. Entered from W_POST, inside the NMI, $1B = 1.
.proc LS_POST
        lda     NET_MODE
        cmp     #2
        beq     :+
        jsr     SES_PUMP
:
.if ::TRACE
        ; test builds: every tick's checksum into a 1024-tick ring
        jsr     LS_CKSUM
        lda     TICK_LO         ; (T & 1023) * 2, TRACE_BUF page aligned
        asl     a
        sta     ZP_PTR
        lda     TICK_HI
        and     #$03
        rol     a
        adc     #>TRACE_BUF
        sta     ZP_PTR+1
        ldy     #0
        lda     CRC_LO
        sta     (ZP_PTR),y
        iny
        lda     CRC_HI
        sta     (ZP_PTR),y
.endif
        lda     TICK_LO
        and     #$3F
        bne     @nocrc
.if ::TRACE = 0
        jsr     LS_CKSUM
.endif
        jsr     RS_RECORD_CRC
        lda     NET_MODE
        cmp     #1
        bne     @nocrc
        lda     #5
        sta     TXBUF
        lda     #FT_CRC
        sta     TXBUF+1
        lda     TICK_LO
        sta     TXBUF+2
        lda     TICK_HI
        sta     TXBUF+3
        lda     CRC_LO
        sta     TXBUF+4
        lda     CRC_HI
        sta     TXBUF+5
        ldx     #6
        jsr     NET_WRITE
@nocrc: inc     TICK_LO
        bne     :+
        inc     TICK_HI
:       lda     NET_MODE
        cmp     #1
        bne     :+
        jsr     RS_PENDING
:       rts
.endproc

; ---------------------------------------------------------------------------
; LS_LOCAL -- this console's input for the tick being captured: controller 1
; (the stock double-read-and-AND). ZP_T2 = controller 2, for SOLO builds.
.proc LS_LOCAL
.if ::FUZZ
        lda     NET_ROLE
        jsr     LS_FUZZ_SIDE    ; X = 0: our stream
        pha
        lda     #1
        ldx     #2
        jsr     LS_FUZZ_STEP    ; the SOLO peer's stream, kept in step
        sta     ZP_T2
        pla
        rts
.else
        jsr     G_READPADS
        lda     G_PAD1
        sta     ZP_T1
        lda     G_PAD2
        sta     ZP_T2
        jsr     G_READPADS
        lda     G_PAD2
        and     ZP_T2
        sta     ZP_T2
        lda     G_PAD1
        and     ZP_T1
        rts
.endif
.endproc

; LS_SOLO_RMT -- SOLO builds: the "peer's" input for T+d.
.proc LS_SOLO_RMT
        lda     ZP_T2
        rts
.endproc

.if ::FUZZ
; LS_FUZZ_SIDE -- A = side (0 host, 1 guest) for our own stream at X = 0.
.proc LS_FUZZ_SIDE
        ldx     #0
        jmp     LS_FUZZ_STEP
.endproc

; LS_FUZZ_STEP -- A = side, X = stream (0 = FUZ, 2 = FUZ2). The input this
; side presses at the tick being captured (T+d). The host side opens with a
; script that picks VERSUS and starts the game; then both sides get a new
; random pad every 8 ticks, Start and Select masked out.
.proc LS_FUZZ_STEP
        sta     ZP_T3
        lda     ZP_PTR2+1       ; t = T + d, the tick this input is for
        bne     @fuzz           ; past 255: the script is long over
        lda     ZP_T3
        bne     @idle           ; the guest side waits out the script
        lda     ZP_PTR2
        cmp     #150
        bcc     @idle
        cmp     #156
        bcc     @sel
        cmp     #190
        bcc     @idle
        cmp     #196
        bcc     @start
@idle:  lda     #0
        rts
@sel:   lda     #$20            ; Select: VERSUS
        rts
@start: lda     #$10            ; Start
        rts
@fuzz:  lda     ZP_PTR2
        and     #7
        bne     @hold
        ; xorshift16 (7, 9, 8)
        lda     FUZ_HI,x
        lsr     a
        lda     FUZ_LO,x
        ror     a
        eor     FUZ_HI,x
        sta     FUZ_HI,x
        ror     a
        eor     FUZ_LO,x
        sta     FUZ_LO,x
        eor     FUZ_HI,x
        sta     FUZ_HI,x
        and     #$CF
        sta     FUZ_CUR,x
@hold:  lda     FUZ_CUR,x
        rts
.endproc
.endif

; ---------------------------------------------------------------------------
; LS_RNG -- step the sim RNG (Galois LFSR, taps $B400) 8 times and hand the
; game its random byte. Replaces the stock main loop's churn of $63.
.proc LS_RNG
        ldx     #8
@l:     lsr     LFSR_HI
        ror     LFSR_LO
        bcc     :+
        lda     LFSR_HI
        eor     #$B4
        sta     LFSR_HI
:       dex
        bne     @l
        lda     LFSR_LO
        sta     G_RNG
        rts
.endproc

; ---------------------------------------------------------------------------
; LS_CKSUM -- Fletcher-style 16-bit sum over the sim state into CRC_LO/HI.
;
; Only state the sim owns: zero page minus the scratch at $00-$07, the NMI
; busy flag, the bank-save bytes, the sound engine ($70-$D7, which runs once
; per tick but is display-adjacent), ours, and the PPU shadows; then the
; object tables at $0300-$06FF and the RNG. OAM ($0200) and the VRAM update
; list ($0700) are display.
.proc LS_CKSUM
        lda     #0
        sta     CRC_LO
        sta     CRC_HI
        tax
@reg:   lda     CK_TBL+2,x
        beq     @tail
        sta     ZP_T1
        lda     CK_TBL,x
        sta     ZP_PTR
        lda     CK_TBL+1,x
        sta     ZP_PTR+1
        ldy     #0
@b:     lda     CRC_LO
        clc
        adc     (ZP_PTR),y
        sta     CRC_LO
        clc
        adc     CRC_HI
        sta     CRC_HI
        iny
        cpy     ZP_T1
        bne     @b
        inx
        inx
        inx
        jmp     @reg
@tail:  ldx     #0
:       lda     CRC_LO
        clc
        adc     LFSR_LO,x
        sta     CRC_LO
        clc
        adc     CRC_HI
        sta     CRC_HI
        inx
        cpx     #2
        bne     :-
        rts
.endproc

; address, count (1-255; an entry of 0 ends the table)
CK_TBL:
        .word   $0008
        .byte   $1B-$08         ; $08-$1A
        .word   $001C
        .byte   $3C-$1C         ; $1C-$3B
        .word   $003E
        .byte   $70-$3E         ; $3E-$6F
        .word   $00D8
        .byte   $F0-$D8         ; $D8-$EF
        .word   $00F5
        .byte   4               ; $F5-$F8 pads
        .word   $00FC
        .byte   2               ; $FC-$FD scroll
        .word   $0300
        .byte   255
        .word   $03FF
        .byte   255
        .word   $04FE
        .byte   255
        .word   $05FD
        .byte   255
        .word   $06FC
        .byte   4               ; $0300-$06FF
        .word   0
        .byte   0

; ---------------------------------------------------------------------------
; LS_GONE -- the peer is gone (PEER_WHY says how). The sim cannot advance
; without the peer's input, so this never returns: NMI off, our own screen
; with the opponent's name and the four field-diagnostic counters (the one
; time a player on real hardware can read them), and a spin until reset.
.proc LS_GONE
        lda     #1
        sta     PEER_SCR
        jsr     UI_OFF
        lda     #0
        sta     $4015           ; the last notes would drone forever
        jsr     UI_INIT
        jsr     UI_END
        lda     PEER_WHY
        beq     @lost
        lda     #<STR_GONE
        ldx     #>STR_GONE
        ldy     #9
        jmp     @say
@lost:  lda     #<STR_LOST
        ldx     #>STR_LOST
        ldy     #8
@say:   sta     ZP_PTR
        stx     ZP_PTR+1
        ldx     #8
        jsr     UI_PRINT
        lda     #<OPP_NAME
        sta     ZP_PTR
        lda     #>OPP_NAME
        sta     ZP_PTR+1
        ldx     #11
        ldy     #12
        jsr     UI_PRINT
        lda     #<STR_RESET
        sta     ZP_PTR
        lda     #>STR_RESET
        sta     ZP_PTR+1
        ldx     #15
        ldy     #10
        jsr     UI_PRINT
        lda     #<STR_DIAG
        sta     ZP_PTR
        lda     #>STR_DIAG
        sta     ZP_PTR+1
        ldx     #19
        ldy     #8
        jsr     UI_PRINT
        jsr     UI_BEGIN
        lda     #21
        sta     UI_ROW
        lda     #9
        sta     UI_COL
        lda     DIAG_SLIP
        jsr     UI_HEX2
        lda     #13
        sta     UI_COL
        lda     DIAG_REJ
        jsr     UI_HEX2
        lda     #17
        sta     UI_COL
        lda     DIAG_TMO
        jsr     UI_HEX2
        lda     #21
        sta     UI_COL
        lda     DIAG_ERR
        jsr     UI_HEX2
        jsr     UI_END
@spin:  jmp     @spin
.endproc

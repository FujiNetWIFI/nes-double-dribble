; text.s -- a text screen for the session and the peer-left notice.
;
; Our screens run with NMI off and own the PPU outright: the font goes into
; CHR-RAM tiles $20-$7F of pattern table 0 (tile number = ASCII, the same
; layout the fn-nes bring-up clients use), text goes into nametable 0. The
; game uploads its own CHR when it starts, and UI_WIPE scrubs what we used
; before handing over, so nothing of ours can leak into its screens.
;
; Writes happen with rendering off (UI_BEGIN ... UI_END). A redraw therefore
; blanks one frame; at lobby refresh rates nobody minds.


; UI_OFF -- NMI and rendering off, now.
.proc UI_OFF
        lda     #0
        sta     PPU_CTRL
        sta     PPU_MASK
        rts
.endproc

; UI_WAITVBL -- wait for the next vblank (NMI is off, so poll).
.proc UI_WAITVBL
        bit     PPU_STATUS
:       bit     PPU_STATUS
        bpl     :-
        rts
.endproc

; UI_INIT -- font, palette, blank nametable; leaves the screen off.
.proc UI_INIT
        jsr     UI_OFF
        jsr     UI_WAITVBL
        ; font: 96 tiles at $0200, plane 0 from FONT, plane 1 zero
        lda     #$02
        sta     PPU_ADDR
        lda     #$00
        sta     PPU_ADDR
        lda     #<FONT
        sta     ZP_PTR
        lda     #>FONT
        sta     ZP_PTR+1
        ldx     #96
@tile:  ldy     #0
:       lda     (ZP_PTR),y
        sta     PPU_DATA
        iny
        cpy     #8
        bne     :-
        lda     #0
        ldy     #8
:       sta     PPU_DATA
        dey
        bne     :-
        lda     ZP_PTR
        clc
        adc     #8
        sta     ZP_PTR
        bcc     :+
        inc     ZP_PTR+1
:       dex
        bne     @tile
        ; palette: black, white text; every sub-palette alike
        lda     #$3F
        sta     PPU_ADDR
        lda     #$00
        sta     PPU_ADDR
        ldx     #8
:       lda     #$0F
        sta     PPU_DATA
        lda     #$30
        sta     PPU_DATA
        lda     #$10
        sta     PPU_DATA
        lda     #$00
        sta     PPU_DATA
        dex
        bne     :-
        jmp     UI_CLS_RAW
.endproc

; UI_CLS_RAW -- nametable 0 to spaces, attributes 0. Screen must be off.
.proc UI_CLS_RAW
        lda     #$20
        sta     PPU_ADDR
        lda     #$00
        sta     PPU_ADDR
        lda     #' '
        ldy     #3              ; 960 tiles = 3 x 256 + 192
        ldx     #0
@p:     sta     PPU_DATA
        inx
        bne     @p
        dey
        bne     @p
        ldx     #192
@r:     sta     PPU_DATA
        dex
        bne     @r
        lda     #0              ; attributes
        ldx     #64
:       sta     PPU_DATA
        dex
        bne     :-
        rts
.endproc

; UI_BEGIN / UI_END -- bracket nametable writes.
.proc UI_BEGIN
        jsr     UI_WAITVBL
        lda     #0
        sta     PPU_MASK
        rts
.endproc

.proc UI_END
        jsr     UI_WAITVBL
        lda     #0
        sta     PPU_CTRL        ; BG from pattern table 0, NMI off
        sta     PPU_SCROLL
        sta     PPU_SCROLL
        lda     #%00001010      ; BG on, leftmost column too
        sta     PPU_MASK
        rts
.endproc

; UI_CLS -- blank the visible screen.
.proc UI_CLS
        jsr     UI_BEGIN
        jsr     UI_CLS_RAW
        jmp     UI_END
.endproc

; UI_AT -- set the PPU address to row UI_ROW, column UI_COL of nametable 0.
.proc UI_AT
        lda     UI_ROW
        lsr     a
        lsr     a
        lsr     a
        ora     #$20
        sta     PPU_ADDR
        lda     UI_ROW
        asl     a
        asl     a
        asl     a
        asl     a
        asl     a
        ora     UI_COL
        sta     PPU_ADDR
        rts
.endproc

; UI_PUTS -- NUL-terminated string at ZP_PTR to (UI_ROW, UI_COL). Inside a
; UI_BEGIN/UI_END bracket.
.proc UI_PUTS
        jsr     UI_AT
        ldy     #0
:       lda     (ZP_PTR),y
        beq     @done
        sta     PPU_DATA
        iny
        bne     :-
@done:  rts
.endproc

; UI_PUTN -- X bytes at ZP_PTR; NUL and anything unprintable as a space.
.proc UI_PUTN
        jsr     UI_AT
        ldy     #0
@l:     lda     (ZP_PTR),y
        cmp     #$20
        bcc     @sp
        cmp     #$7F
        bcc     @ok
@sp:    lda     #' '
@ok:    sta     PPU_DATA
        iny
        dex
        bne     @l
        rts
.endproc

; UI_HEX2 -- A as two hex digits at (UI_ROW, UI_COL).
.proc UI_HEX2
        pha
        jsr     UI_AT
        pla
        pha
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        jsr     @dig
        pla
        and     #$0F
@dig:   cmp     #10
        bcc     :+
        adc     #'A'-'0'-10-1
:       adc     #'0'
        sta     PPU_DATA
        rts
.endproc

; UI_PRINT -- convenience: X = row, Y = column, ZP_PTR = string; one
; bracketed write.
.proc UI_PRINT
        stx     UI_ROW
        sty     UI_COL
        jsr     UI_BEGIN
        jsr     UI_PUTS
        jmp     UI_END
.endproc

; UI_WIPE -- before the game gets the PPU back: font tiles, both nametables
; and the palette to zero. Screen off, NMI off.
.proc UI_WIPE
        jsr     UI_WAITVBL
        lda     #$02
        sta     PPU_ADDR
        lda     #$00
        sta     PPU_ADDR
        tax
        ldy     #6              ; $0200-$07FF
:       sta     PPU_DATA
        inx
        bne     :-
        dey
        bne     :-
        lda     #$20
        sta     PPU_ADDR
        lda     #$00
        sta     PPU_ADDR
        ldy     #8              ; $2000-$27FF
:       sta     PPU_DATA
        inx
        bne     :-
        dey
        bne     :-
        lda     #$3F
        sta     PPU_ADDR
        lda     #$00
        sta     PPU_ADDR
        lda     #$0F
        ldx     #32
:       sta     PPU_DATA
        dex
        bne     :-
        lda     #0
        sta     PPU_SCROLL
        sta     PPU_SCROLL
        rts
.endproc

        .segment "RODATA"
FONT:
        .include "ui/font.inc"
        .segment "CODE"

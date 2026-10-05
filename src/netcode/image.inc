; image.inc -- the resync state image (see resync.s).
;
;   0    .. 255     $0000-$00FF  zero page (applied minus IMG_SKIP bytes)
;   256  .. 1791    $0200-$07FF  OAM page, objects, VRAM update list
;   1792 .. 3839    PPU $2000-$27FF  both nametables (vertical mirroring)
;   3840 .. 3871    PPU $3F00-$3F1F  palette
;   3872 .. 3873    LFSR_LO, LFSR_HI (the sim RNG)
; The stack page is not in it: the receiver applies the image from inside
; its own NMI, three calls deep.

IMG_RAM2        = 256
IMG_VRAM        = 1792
IMG_PAL         = 3840
IMG_LFSR        = 3872
IMG_TOTAL       = 3874
RS_CHUNK        = 96            ; data bytes per STATE frame (len = n + 3)

; ============================================================================
; video.s - palette load and video/overlay bring-up
; ----------------------------------------------------------------------------
; Included by kernel.s into the single kernel translation unit (after
; kernel.inc), so every VIDX_*/CMD_* constant and the KZEROPAGE scratch are
; already in scope and no .import/.export plumbing is required.
; ============================================================================

.segment "CODE"

; ----------------------------------------------------------------------------
; video_load_palettes - load vibrant RGB565 palette banks 0-7.
; Palette 0 is the default console palette: blue transparent/background slot
; and white foreground text. The other banks provide convenient text colors.
; ----------------------------------------------------------------------------
video_load_palettes:
        lda #<palette_data
        sta KPTR
        lda #>palette_data
        sta KPTR+1
        lda #VIDX_PALETTE_0
        sta KTMP
@bank:
        lda KTMP
        sta IDXA_SELECT
        ldy #$00
@byte:
        lda (KPTR),y
        sta IDXA_PORT
        iny
        cpy #$10
        bne @byte

        clc
        lda KPTR
        adc #$10
        sta KPTR
        bcc @no_carry
        inc KPTR+1
@no_carry:
        inc KTMP
        lda KTMP
        cmp #(VIDX_PALETTE_0 + PALETTE_COUNT)
        bne @bank
        rts

; ----------------------------------------------------------------------------
; video_init - configure palette/font state, enable overlay, request refresh
; ----------------------------------------------------------------------------
video_init:
        jsr video_load_palettes

        ; MIA split-loads the default font: ASCII text into CHR bank 0 plane 0
        ; (overlay primary bank) and the graphics/line set into CHR bank 1 plane 0
        ; (overlay alternate bank). The overlay renders plane 0, so tile code N is
        ; the glyph for ASCII codepoint N and console output needs no screen-code
        ; translation. Per-cell CHR_ALT selects text (bank 0) vs graphics (bank 1).
        lda #VIDX_BANK_SELECT
        sta IDXA_SELECT
        lda #VIDEO_CHR_BANK_DEFAULT
        sta IDXA_PORT           ; background bank
        sta IDXA_PORT           ; background alt bank
        sta IDXA_PORT           ; overlay bank (text, primary)
        lda #VIDEO_CHR_BANK_GRAPHICS
        sta IDXA_PORT           ; overlay alt bank (graphics)
        lda #VIDEO_CHR_BANK_DEFAULT
        sta IDXA_PORT           ; sprite bank

        lda #VIDX_CHR_1BPP
        sta IDXA_SELECT
        lda #CHR_1BPP_BANKS_TEXT_GFX
        sta IDXA_PORT
        lda #CHR_1BPP_PLANES_OVERLAY0
        sta IDXA_PORT

        jsr init_scroll_indexes

        ; Palette 0 color 0 is the blue screen backdrop.
        lda #VIDX_BACKDROP_COLOR
        sta IDXA_SELECT
        lda #BACKDROP_BLUE
        sta IDXA_PORT

        ; Enable video output.
        lda #VIDEO_MODE_ENABLE
        sta CMD_PARAM1
        stz CMD_PARAM2
        stz CMD_PARAM3
        lda #CMD_VIDEO_SET_MODE
        sta CMD_TRIGGER

        ; Enable the overlay layer (stream one byte through index $81).
        lda #VIDX_LAYER_ENABLE
        sta IDXA_SELECT
        lda #LAYER_OVERLAY
        sta IDXA_PORT

        ; Make sure the client picks up the whole initial screen.
        lda #CMD_VIDEO_FULL_REFRESH
        sta CMD_TRIGGER
        rts

; ----------------------------------------------------------------------------
; init_scroll_indexes - reserve $F0-$F3 as fixed DMA source/destination pairs.
; ----------------------------------------------------------------------------
init_scroll_indexes:
        lda #KIDX_SCROLL_NT_SRC
        sta IDXA_SELECT
        lda #(OVNT_ADDR_L + SCR_COLS)
        ldx #OVNT_ADDR_M
        ldy #OVNT_ADDR_H
        jsr set_idxa_addr
        lda #<(OVNT_ADDR_L + (SCR_ROWS * SCR_COLS))
        ldx #(OVNT_ADDR_M + >(OVNT_ADDR_L + (SCR_ROWS * SCR_COLS)))
        ldy #OVNT_ADDR_H
        jsr set_idxa_limit

        lda #KIDX_SCROLL_NT_DST
        sta IDXA_SELECT
        lda #OVNT_ADDR_L
        ldx #OVNT_ADDR_M
        ldy #OVNT_ADDR_H
        jsr set_idxa_addr

        lda #KIDX_SCROLL_ATTR_SRC
        sta IDXA_SELECT
        lda #(OVATTR_ADDR_L + SCR_COLS)
        ldx #OVATTR_ADDR_M
        ldy #OVATTR_ADDR_H
        jsr set_idxa_addr
        lda #<(OVATTR_ADDR_L + (SCR_ROWS * SCR_COLS))
        ldx #(OVATTR_ADDR_M + >(OVATTR_ADDR_L + (SCR_ROWS * SCR_COLS)))
        ldy #OVATTR_ADDR_H
        jsr set_idxa_limit

        lda #KIDX_SCROLL_ATTR_DST
        sta IDXA_SELECT
        lda #OVATTR_ADDR_L
        ldx #OVATTR_ADDR_M
        ldy #OVATTR_ADDR_H
        jsr set_idxa_addr
        rts

; ----------------------------------------------------------------------------
; Read-only data
; ----------------------------------------------------------------------------
.segment "RODATA"
; Eight RGB565 colors per palette, little-endian. For 1bpp overlay text,
; color index 0 is transparent/backdrop and color index 1 is the glyph color.
palette_data:
        ; palette 0: default console (blue backdrop, white text)
        .byte $1F,$1A, $FF,$FF, $00,$00, $00,$F8
        .byte $60,$FC, $C0,$FE, $E0,$07, $5F,$07
        ; palette 1: red foreground
        .byte $1F,$1A, $00,$F8, $FF,$FF, $60,$FC
        .byte $C0,$FE, $E0,$07, $5F,$07, $7F,$FA
        ; palette 2: orange foreground
        .byte $1F,$1A, $60,$FC, $FF,$FF, $00,$F8
        .byte $C0,$FE, $E0,$07, $5F,$07, $7F,$FA
        ; palette 3: yellow foreground
        .byte $1F,$1A, $C0,$FE, $FF,$FF, $00,$F8
        .byte $60,$FC, $E0,$07, $5F,$07, $7F,$FA
        ; palette 4: green foreground
        .byte $1F,$1A, $E0,$07, $FF,$FF, $00,$F8
        .byte $60,$FC, $C0,$FE, $5F,$07, $7F,$FA
        ; palette 5: cyan foreground
        .byte $1F,$1A, $5F,$07, $FF,$FF, $00,$F8
        .byte $60,$FC, $C0,$FE, $E0,$07, $7F,$FA
        ; palette 6: magenta foreground
        .byte $1F,$1A, $7F,$FA, $FF,$FF, $00,$F8
        .byte $60,$FC, $C0,$FE, $E0,$07, $5F,$07
        ; palette 7: bright blue-white foreground
        .byte $1F,$1A, $FF,$6A, $FF,$FF, $00,$F8
        .byte $60,$FC, $C0,$FE, $E0,$07, $5F,$07

; ============================================================================
; video.s - video and overlay bring-up
; ----------------------------------------------------------------------------
; Included by kernel.s into the single kernel translation unit (after
; kernel.inc), so every MIA_* constant and the KZEROPAGE scratch are
; already in scope and no .import/.export plumbing is required.
; ============================================================================

.segment "KERNCODE"

; ----------------------------------------------------------------------------
; video_init - configure font state, enable overlay, request refresh
; ----------------------------------------------------------------------------
video_init:
        ; MIA loads the default font and palette when video starts. With the
        ; clascii charset, CHR bank 0 plane 0 (overlay primary bank) holds the
        ; 256 glyphs and bank 1 plane 0 (overlay alternate bank) the same glyphs
        ; reversed; the older openroms charset puts a graphics/line set in bank 1.
        ; The overlay renders plane 0, so tile code N is the glyph for ASCII
        ; codepoint N and console output needs no screen-code translation.
        ; Per-cell CHR_ALT selects bank 1.
        lda #MIA_VIDEO_INDEX_BANK_SELECT
        sta IDXA_SELECT
        lda #VIDEO_CHR_BANK_DEFAULT
        sta IDXA_PORT           ; background bank
        sta IDXA_PORT           ; background alt bank
        sta IDXA_PORT           ; overlay bank (text, primary)
        lda #VIDEO_CHR_BANK_GRAPHICS
        sta IDXA_PORT           ; overlay alt bank (graphics)
        lda #VIDEO_CHR_BANK_DEFAULT
        sta IDXA_PORT           ; sprite bank

        lda #MIA_VIDEO_INDEX_CHR_1BPP
        sta IDXA_SELECT
        lda #CHR_1BPP_BANKS_TEXT_GFX
        sta IDXA_PORT
        lda #CHR_1BPP_PLANES_OVERLAY0
        sta IDXA_PORT

        jsr init_scroll_indexes

        ; Palette 0 color 0 is the blue screen backdrop.
        lda #MIA_VIDEO_INDEX_BACKDROP_COLOR
        sta IDXA_SELECT
        lda #BACKDROP_BLUE
        sta IDXA_PORT

        ; Enable video output.
        lda #MIA_VIDEO_MODE_ENABLE
        sta CMD_PARAM1
        stz CMD_PARAM2
        stz CMD_PARAM3
        lda #MIA_CMD_VIDEO_SET_MODE
        sta CMD_TRIGGER

        ; Enable the overlay layer (stream one byte through index $81).
        lda #MIA_VIDEO_INDEX_LAYER_ENABLE
        sta IDXA_SELECT
        lda #MIA_VIDEO_LAYER_OVERLAY
        sta IDXA_PORT

        ; Make sure the client picks up the whole initial screen.
        lda #MIA_CMD_VIDEO_FORCE_FULL_REFRESH
        sta CMD_TRIGGER
        rts

; ----------------------------------------------------------------------------
; set_backdrop - set the screen backdrop color. In: A = backdrop selector
; (bits 0-2 = color index, bits 3-6 = palette bank; see MIA_VIDEO_INDEX_BACKDROP_COLOR).
; The renderer repaints the backdrop from VRAM every frame, so writing the
; selector is enough - no refresh command needed. The two-register window A
; write is fenced with sei so a cursor-blink IRQ (cursor_show/hide rebind
; window A to the overlay index) can't land between the select and the data
; write; the IRQ also restores window A through MIA_CTX, so the fence is a
; second guard. Preserves X/Y; returns with A = selector.
; ----------------------------------------------------------------------------
set_backdrop:
        php                     ; save the caller's interrupt-enable state
        sei
        pha
        lda #MIA_VIDEO_INDEX_BACKDROP_COLOR
        sta IDXA_SELECT
        pla                     ; A = selector again
        sta IDXA_PORT
        plp                     ; restore interrupts (re-enable if they were on)
        rts

; ----------------------------------------------------------------------------
; init_scroll_indexes - reserve $F0-$F3 as fixed DMA source/destination pairs.
; ----------------------------------------------------------------------------
init_scroll_indexes:
        lda #KIDX_SCROLL_NT_SRC
        sta IDXA_SELECT
        lda #<(MIA_VIDEO_OVERLAY_NT_OFFSET + SCR_COLS)
        ldx #>MIA_VIDEO_OVERLAY_NT_OFFSET
        ldy #^MIA_VIDEO_OVERLAY_NT_OFFSET
        jsr set_idxa_addr
        lda #<(MIA_VIDEO_OVERLAY_NT_OFFSET + (SCR_ROWS * SCR_COLS))
        ldx #>(MIA_VIDEO_OVERLAY_NT_OFFSET + (SCR_ROWS * SCR_COLS))
        ldy #^MIA_VIDEO_OVERLAY_NT_OFFSET
        jsr set_idxa_limit

        lda #KIDX_SCROLL_NT_DST
        sta IDXA_SELECT
        lda #<MIA_VIDEO_OVERLAY_NT_OFFSET
        ldx #>MIA_VIDEO_OVERLAY_NT_OFFSET
        ldy #^MIA_VIDEO_OVERLAY_NT_OFFSET
        jsr set_idxa_addr

        lda #KIDX_SCROLL_ATTR_SRC
        sta IDXA_SELECT
        lda #<(MIA_VIDEO_OVERLAY_ATTR_OFFSET + SCR_COLS)
        ldx #>MIA_VIDEO_OVERLAY_ATTR_OFFSET
        ldy #^MIA_VIDEO_OVERLAY_ATTR_OFFSET
        jsr set_idxa_addr
        lda #<(MIA_VIDEO_OVERLAY_ATTR_OFFSET + (SCR_ROWS * SCR_COLS))
        ldx #>(MIA_VIDEO_OVERLAY_ATTR_OFFSET + (SCR_ROWS * SCR_COLS))
        ldy #^MIA_VIDEO_OVERLAY_ATTR_OFFSET
        jsr set_idxa_limit

        lda #KIDX_SCROLL_ATTR_DST
        sta IDXA_SELECT
        lda #<MIA_VIDEO_OVERLAY_ATTR_OFFSET
        ldx #>MIA_VIDEO_OVERLAY_ATTR_OFFSET
        ldy #^MIA_VIDEO_OVERLAY_ATTR_OFFSET
        jsr set_idxa_addr
        rts

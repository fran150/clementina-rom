; ============================================================================
; console.s - overlay text console: clear, output, scroll, cursor, index addr
; ----------------------------------------------------------------------------
; Included by kernel.s into the single kernel translation unit (after
; kernel.inc). Drives the overlay nametable/attribute planes via window A.
; ============================================================================

.segment "CODE"

; ----------------------------------------------------------------------------
; clrscr - fill the overlay with spaces and home the cursor
; Binds the overlay index ($B8) to window A and streams from the base.
; ----------------------------------------------------------------------------
clrscr:
        lda #VIDX_OVERLAY_NT
        sta IDXA_SELECT
        lda #OVNT_ADDR_L
        ldx #OVNT_ADDR_M
        ldy #OVNT_ADDR_H
        jsr set_idxa_addr

        ; Write SCR_COLS*SCR_ROWS (1000) spaces; index $B8 auto-steps.
        lda #<(SCR_COLS * SCR_ROWS)
        sta KCNT
        lda #>(SCR_COLS * SCR_ROWS)
        sta KCNT+1
@fill:
        lda #' '
        sta IDXA_PORT
        lda KCNT
        bne @dec
        dec KCNT+1
@dec:
        dec KCNT
        lda KCNT
        ora KCNT+1
        bne @fill

        lda #VIDX_OVERLAY_ATTR
        sta IDXA_SELECT
        lda #OVATTR_ADDR_L
        ldx #OVATTR_ADDR_M
        ldy #OVATTR_ADDR_H
        jsr set_idxa_addr

        ; Match every cleared cell to the current text color.
        lda #<(SCR_COLS * SCR_ROWS)
        sta KCNT
        lda #>(SCR_COLS * SCR_ROWS)
        sta KCNT+1
@attr_fill:
        lda TEXT_ATTR
        sta IDXA_PORT
        lda KCNT
        bne @attr_dec
        dec KCNT+1
@attr_dec:
        dec KCNT
        lda KCNT
        ora KCNT+1
        bne @attr_fill

        stz CURSOR_X
        stz CURSOR_Y
        stz CURSOR_VISIBLE
        rts

; ----------------------------------------------------------------------------
; chrout - write the character in A to the console at the cursor
; Handles CR ($0D = newline), LF ($0A = ignored), BS ($08), FF ($0C = clear),
; printable bytes. Preserves A/X/Y.
; ----------------------------------------------------------------------------
chrout:
        sta KCHR
        pha
        phx
        phy
        jsr cursor_hide
        cmp #$0D
        beq @cr
        cmp #$0A
        beq @done               ; ignore LF; CR does the newline
        cmp #$08
        beq @bs
        cmp #$0C
        beq @ff                 ; form feed: clear screen

        ; Printable: aim the overlay indexes at the cursor cell and write the
        ; tile code plus its palette attribute. The font is ASCII-ordered, so
        ; the tile code is the ASCII byte itself (no screen-code translation).
        jsr cursor_to_idxa
        lda KCHR
        sta IDXA_PORT
        jsr cursor_attr_to_idxa
        lda TEXT_ATTR
        sta IDXA_PORT
        inc CURSOR_X
        lda CURSOR_X
        cmp #SCR_COLS
        bcc @done
        stz CURSOR_X            ; wrap to next line
        jsr newline
        bra @done

@cr:
        stz CURSOR_X
        jsr newline
        bra @done

@ff:
        jsr clrscr              ; clear screen and home the cursor
        bra @done

@bs:
        lda CURSOR_X
        beq @done               ; keep it simple: don't back past column 0
        dec CURSOR_X
        jsr cursor_to_idxa
        lda #' '
        sta IDXA_PORT           ; erase the character under the cursor
        jsr cursor_attr_to_idxa
        lda TEXT_ATTR
        sta IDXA_PORT

@done:
        jsr cursor_show
        ply
        plx
        pla
        rts

; ----------------------------------------------------------------------------
; newline - advance cursor one row, scrolling at the bottom
; ----------------------------------------------------------------------------
newline:
        inc CURSOR_Y
        lda CURSOR_Y
        cmp #SCR_ROWS
        bcc @ok
        lda #SCR_ROWS-1
        sta CURSOR_Y
        jsr scroll_up
@ok:
        rts

; ----------------------------------------------------------------------------
; scroll_up - move rows 1..23 up one, blank the last row.
; Uses MIA DMA via CMD_COPY_INDEXES. A zero byte count copies from source
; current address up to source limit address, without moving either index.
; ----------------------------------------------------------------------------
scroll_up:
        lda #KIDX_SCROLL_NT_SRC
        ldx #KIDX_SCROLL_NT_DST
        jsr dma_copy_indexes

        ; Blank the last nametable row.
        lda #VIDX_OVERLAY_NT
        sta IDXA_SELECT
        lda #<(OVNT_ADDR_L + ((SCR_ROWS-1) * SCR_COLS))
        ldx #(OVNT_ADDR_M + >(OVNT_ADDR_L + ((SCR_ROWS-1) * SCR_COLS)))
        ldy #OVNT_ADDR_H
        jsr set_idxa_addr
        ldx #SCR_COLS
        lda #' '
@blank:
        sta IDXA_PORT
        dex
        bne @blank

        ; Scroll matching overlay attributes so colored text keeps its palette.
        lda #KIDX_SCROLL_ATTR_SRC
        ldx #KIDX_SCROLL_ATTR_DST
        jsr dma_copy_indexes

        lda #VIDX_OVERLAY_ATTR
        sta IDXA_SELECT
        lda #<(OVATTR_ADDR_L + ((SCR_ROWS-1) * SCR_COLS))
        ldx #(OVATTR_ADDR_M + >(OVATTR_ADDR_L + ((SCR_ROWS-1) * SCR_COLS)))
        ldy #OVATTR_ADDR_H
        jsr set_idxa_addr
        ldx #SCR_COLS
        lda TEXT_ATTR
@attr_blank:
        sta IDXA_PORT
        dex
        bne @attr_blank
        rts

dma_copy_indexes:
        sta CMD_PARAM1
        txa
        sta CMD_PARAM2
        stz CMD_PARAM3          ; zero = copy until source index limit
        lda #CMD_COPY_INDEXES
        sta CMD_TRIGGER
wait_cmd_dma:
        lda STATUS_L
        and #(MIA_STAT_CMD_RUNNING | MIA_STAT_DMA_RUNNING)
        bne wait_cmd_dma
        rts

; ----------------------------------------------------------------------------
; cursor_to_idxa - bind the overlay index ($B8) to window A and set its current
; address to the cell for CURSOR_X/Y. Computes P = CURSOR_Y*40 + CURSOR_X and
; the 24-bit MIA address ($10080 + P).
; ----------------------------------------------------------------------------
cursor_to_idxa:
        lda #VIDX_OVERLAY_NT
        sta IDXA_SELECT         ; window A -> overlay index (CFG_IDXA_* targets it)
        jsr cursor_offset_to_ktmp
        lda KTMP
        clc
        adc #OVNT_ADDR_L        ; + $80
        sta KTMP                ; address low
        lda KTMP+1
        adc #OVNT_ADDR_M        ; + carry
        sta KTMP+1              ; address mid
        lda KTMP                ; A = low
        ldx KTMP+1              ; X = mid
        ldy #OVNT_ADDR_H        ; Y = high
        jsr set_idxa_addr
        rts

cursor_attr_to_idxa:
        lda #VIDX_OVERLAY_ATTR
        sta IDXA_SELECT
        jsr cursor_offset_to_ktmp
        lda KTMP
        clc
        adc #OVATTR_ADDR_L
        sta KTMP
        lda KTMP+1
        adc #OVATTR_ADDR_M
        sta KTMP+1
        lda KTMP
        ldx KTMP+1
        ldy #OVATTR_ADDR_H
        jsr set_idxa_addr
        rts

cursor_offset_to_ktmp:
        ; P = CURSOR_Y * 40   (40 = 5 * 8; y<=24 so 5*y <= 120 fits 8 bits)
        lda CURSOR_Y
        asl
        asl                     ; 4y
        clc
        adc CURSOR_Y            ; 5y
        sta KTMP
        stz KTMP+1
        asl KTMP
        rol KTMP+1              ; 10y
        asl KTMP
        rol KTMP+1              ; 20y
        asl KTMP
        rol KTMP+1              ; 40y
        ; P += CURSOR_X
        lda KTMP
        clc
        adc CURSOR_X
        sta KTMP
        lda KTMP+1
        adc #$00
        sta KTMP+1
        rts

; ----------------------------------------------------------------------------
; cursor_show / cursor_hide - draw and restore a software text cursor.
; The cursor is stored directly in the overlay cell, so these routines save the
; underlying tile and attribute before drawing and restore them before output.
; ----------------------------------------------------------------------------
cursor_show:
        pha
        phx
        phy
        lda CURSOR_VISIBLE
        bne @done

        jsr cursor_to_idxa
        lda IDXA_PORT
        sta CURSOR_SAVE_CHR

        jsr cursor_attr_to_idxa
        lda IDXA_PORT
        sta CURSOR_SAVE_ATTR
        lda TEXT_ATTR
        sta IDXA_PORT

        jsr cursor_to_idxa
        lda #CURSOR_TILE
        sta IDXA_PORT
        lda #$01
        sta CURSOR_VISIBLE
@done:
        ply
        plx
        pla
        rts

cursor_hide:
        pha
        phx
        phy
        lda CURSOR_VISIBLE
        beq @done

        jsr cursor_to_idxa
        lda CURSOR_SAVE_CHR
        sta IDXA_PORT

        jsr cursor_attr_to_idxa
        lda CURSOR_SAVE_ATTR
        sta IDXA_PORT
        stz CURSOR_VISIBLE
@done:
        ply
        plx
        pla
        rts

; ----------------------------------------------------------------------------
; set_idxa_addr / set_idxa_limit - set the current/limit address of the index
; selected in window A. In: A = addr low, X = addr mid, Y = addr high.
; The matching index must already be bound to the window.
; ----------------------------------------------------------------------------
set_idxa_addr:
        pha
        lda #CFG_IDXA_ADDR_L
        sta CFG_SELECT
        pla
        sta CFG_PORT
        lda #CFG_IDXA_ADDR_M
        sta CFG_SELECT
        stx CFG_PORT
        lda #CFG_IDXA_ADDR_H
        sta CFG_SELECT
        sty CFG_PORT
        rts

set_idxa_limit:
        pha
        lda #CFG_IDXA_LIMIT_L
        sta CFG_SELECT
        pla
        sta CFG_PORT
        lda #CFG_IDXA_LIMIT_M
        sta CFG_SELECT
        stx CFG_PORT
        lda #CFG_IDXA_LIMIT_H
        sta CFG_SELECT
        sty CFG_PORT
        rts

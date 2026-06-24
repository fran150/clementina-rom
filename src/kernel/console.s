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

        ; Each cleared row is its own (blank) logical line.
        ldx #SCR_ROWS-1
        lda #LINK_START
@link_init:
        sta LINE_LINK,x
        dex
        bpl @link_init
        rts

; ----------------------------------------------------------------------------
; chrout - write the character in A to the console at the cursor
; Handles CR ($0D = newline), LF ($0A = ignored), BS ($08), FF ($0C = clear),
; the cursor moves (CRSR up/down/left/right) and HOME, and printable bytes.
; Cursor moves only reposition CURSOR_X/Y; they clamp at the screen edges
; (no scroll on move) and wrap left/right between rows. Preserves A/X/Y.
;
; The control handlers sit right after the dispatch so each cmp/beq reaches
; them with a short branch; cross-routine exits use jmp because the routine is
; longer than a single relative branch can span.
; ----------------------------------------------------------------------------
chrout:
        sta KCHR
        pha
        phx
        phy
        jsr cursor_hide
        cmp #CHR_CR
        bne :+
        jmp @cr
:       cmp #CHR_LF
        bne :+
        jmp @done               ; ignore LF; CR does the newline
:       cmp #CHR_BS
        bne :+
        jmp @bs
:       cmp #CHR_FF
        bne :+
        jmp @ff
:       cmp #CHR_CRSR_RIGHT
        bne :+
        jmp @crsr_right
:       cmp #CHR_CRSR_LEFT
        bne :+
        jmp @crsr_left
:       cmp #CHR_CRSR_UP
        bne :+
        jmp @crsr_up
:       cmp #CHR_CRSR_DOWN
        bne :+
        jmp @crsr_down
:       cmp #CHR_HOME
        bne :+
        jmp @home
:       jmp @printable          ; not a control code: draw the glyph

@cr:
        stz CURSOR_X
        jsr newline
        ldx CURSOR_Y            ; CR begins a fresh logical line
        lda #LINK_START
        sta LINE_LINK,x
        jmp @done

@ff:
        jsr clrscr              ; clear screen and home the cursor
        jmp @done

@bs:
        lda CURSOR_X
        beq @bs_done            ; keep it simple: don't back past column 0
        dec CURSOR_X
        jsr cursor_to_idxa
        lda #' '
        sta IDXA_PORT           ; erase the character under the cursor
        jsr cursor_attr_to_idxa
        lda TEXT_ATTR
        sta IDXA_PORT
@bs_done:
        jmp @done

@home:
        stz CURSOR_X
        stz CURSOR_Y
        jmp @done

@crsr_up:
        lda CURSOR_Y
        beq @crsr_up_done       ; already at the top row
        dec CURSOR_Y
@crsr_up_done:
        jmp @done

@crsr_down:
        lda CURSOR_Y
        cmp #SCR_ROWS-1
        bcs @crsr_down_done     ; already at the bottom row (no scroll on move)
        inc CURSOR_Y
@crsr_down_done:
        jmp @done

@crsr_left:
        lda CURSOR_X
        bne @crsr_left_step
        lda CURSOR_Y
        beq @crsr_left_done     ; top-left corner: stay put
        dec CURSOR_Y            ; wrap to the end of the previous row
        lda #SCR_COLS-1
        sta CURSOR_X
        bra @crsr_left_done
@crsr_left_step:
        dec CURSOR_X
@crsr_left_done:
        jmp @done

@crsr_right:
        lda CURSOR_X
        cmp #SCR_COLS-1
        bcc @crsr_right_step
        lda CURSOR_Y
        cmp #SCR_ROWS-1
        bcs @crsr_right_done    ; bottom-right corner: stay put (no scroll on move)
        inc CURSOR_Y            ; wrap to the start of the next row
        stz CURSOR_X
        bra @crsr_right_done
@crsr_right_step:
        inc CURSOR_X
@crsr_right_done:
        jmp @done

@printable:
        ; Draw the byte as a tile. The font is ASCII-ordered, so the tile code is
        ; the ASCII byte itself (no screen-code translation).
        lda KCHR
        jsr put_glyph_raw

@done:
        jsr cursor_show
        ply
        plx
        pla
        rts

; ----------------------------------------------------------------------------
; chrout_glyph - draw A as a raw overlay tile, NEVER interpreting it as a control
; code (KERN_CHROUT_GLYPH). The console control bytes ($0D, $11/$13/$1D and the
; high $91/$9D, ...) overlap the glyph codes that Phase 5's glyph modes and styled
; strings produce, so the editor's glyph echo and STRPRT_STYLED route here instead
; of chrout to keep e.g. tile $9D a glyph rather than a cursor-left. Preserves
; A/X/Y. See docs/phase5-charset-keyboard.md.
; ----------------------------------------------------------------------------
chrout_glyph:
        phy
        phx
        pha
        jsr cursor_hide         ; preserves A/X/Y
        pla
        pha                     ; A = tile; keep a copy to honor the A-preserved contract
        jsr put_glyph_raw       ; draws + advances; clobbers A/X/Y, KTMP, KCHR
        jsr cursor_show
        pla
        plx
        ply
        rts

; ----------------------------------------------------------------------------
; put_glyph_raw - draw tile A at the cursor with the TEXT_ATTR pen, then advance
; the cursor: wrap to the next row (scrolling at the bottom) and mark a wrapped
; row as a logical-line continuation. Assumes the cursor is hidden. Shared by
; chrout's printable path and chrout_glyph. Clobbers A/X/Y, KTMP, KCHR.
; ----------------------------------------------------------------------------
put_glyph_raw:
        sta KCHR
        jsr cursor_to_idxa
        lda KCHR
        sta IDXA_PORT
        jsr cursor_attr_to_idxa
        lda TEXT_ATTR
        sta IDXA_PORT
        inc CURSOR_X
        lda CURSOR_X
        cmp #SCR_COLS
        bcc @ret
        stz CURSOR_X            ; wrap to next line
        jsr newline
        ldx CURSOR_Y            ; the wrapped row continues the logical line
        stz LINE_LINK,x
@ret:
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

        ; Scroll the logical-line link table up with the rows. The new bottom row
        ; starts as its own logical line; a caller that scrolled because of a wrap
        ; re-marks it as a continuation afterward.
        ldx #$00
@link_scroll:
        lda LINE_LINK+1,x
        sta LINE_LINK,x
        inx
        cpx #SCR_ROWS-1
        bne @link_scroll
        lda #LINK_START
        sta LINE_LINK + (SCR_ROWS-1)
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
; cursor_indicator_tile - pick the cursor glyph that previews editor state
; (Phase 5, §4.6): ESC-pending -> $F8; Paint -> $F9; otherwise glyph mode 0/1/2
; as $FA+mode, or the reversed art $FD+mode when the pen's CHR_ALT bit is set.
; Reverse is shown by glyph swap (not CHR_ALT) so the solid mode-0 square stays
; visible on blink. Returns the tile in A; clobbers X; leaves KTMP alone.
; ----------------------------------------------------------------------------
cursor_indicator_tile:
        lda EDIT_CMD_PENDING
        beq @notpending
        lda #CUR_TILE_PENDING
        rts
@notpending:
        lda EDIT_PAINT
        beq @notpaint
        lda #CUR_TILE_PAINT
        rts
@notpaint:
        ldx #CUR_TILE_MODE0
        lda TEXT_ATTR
        and #$80                ; reverse bit -> use the reversed indicator art
        beq @base
        ldx #CUR_TILE_RMODE0
@base:
        txa
        clc
        adc EDIT_MODE           ; + glyph mode (0/1/2)
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

        ; $B8/$B9 auto-step after reads. Re-seek before drawing the preview so
        ; the cursor changes this cell, not the next one.
        jsr cursor_attr_to_idxa
        lda TEXT_ATTR
        and #$7F                ; preview the pen, but never CHR_ALT (would blank the square)
        sta IDXA_PORT

        jsr cursor_to_idxa
        jsr cursor_indicator_tile
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

cursor_toggle:
        pha
        lda CURSOR_VISIBLE
        bne :+
        pla
        jmp cursor_show
:       pla
        jmp cursor_hide

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

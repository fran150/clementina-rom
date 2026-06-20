; ============================================================================
; editor.s - C64-style full-screen line editor (KERN_EDITKEY)
; ----------------------------------------------------------------------------
; Included by kernel.s. KERN_EDITKEY runs an interactive screen editor and hands
; BASIC's line input one harvested character per call. The screen is the buffer:
; typing, cursor moves, and backspace edit overlay cells directly (through
; CHROUT). On RETURN the whole logical line under the cursor is read back
; ("harvested") from the overlay. The line-link table (LINE_LINK) records which
; rows start a logical line vs. continue the one above, so a wrapped line - or a
; previously listed line the cursor was moved onto - harvests as a unit.
;
; GET stays on the raw single-char CHRIN; only BASIC's GETLN calls KERN_EDITKEY,
; so single-key reads are unaffected.
; ============================================================================

.segment "CODE"

; ----------------------------------------------------------------------------
; editkey - return the next character of the edited logical line (KERN_EDITKEY).
; When idle, runs the interactive editor; then doles the harvested bytes followed
; by a terminating CR, then returns to idle for the next line.
; ----------------------------------------------------------------------------
editkey:
        lda EDIT_STATE
        bne @doling
        jsr edit_line           ; fills EDIT_BUF/EDIT_LEN, EDIT_IDX = 0
        lda #$01
        sta EDIT_STATE
@doling:
        lda EDIT_IDX
        cmp EDIT_LEN
        bcc @dole
        stz EDIT_STATE          ; whole line handed out: emit CR, then go idle
        lda #CHR_CR
        rts
@dole:
        ldx EDIT_IDX
        inc EDIT_IDX
        lda EDIT_BUF,x
        rts

; ----------------------------------------------------------------------------
; edit_line - interactive screen edit until RETURN, then harvest the line and
; drop the cursor to the line below it.
; ----------------------------------------------------------------------------
edit_line:
        lda CURSOR_X
        sta EDIT_START_X        ; where this input began (past any printed prompt)
        lda CURSOR_Y
        sta EDIT_START_Y
@loop:
        jsr chrin               ; A = key (cursor shown while waiting, hidden on return)
        cmp #CHR_CR
        beq @enter
        cmp #CHR_BS
        beq @del_left           ; backspace: gap-closing delete to the left
        cmp #CHR_DEL_FWD
        beq @del_fwd            ; delete: gap-closing delete at the cursor
        cmp #CHR_INSERT
        beq @insert             ; insert: open a gap at the cursor
        jsr chrout              ; echo: draw / move / overtype directly on the overlay
        bra @loop
@del_left:
        jsr edit_delete_left
        bra @loop
@del_fwd:
        jsr edit_delete_fwd
        bra @loop
@insert:
        jsr edit_insert
        bra @loop
@enter:
        jsr harvest_line        ; overlay -> EDIT_BUF/EDIT_LEN, EDIT_IDX = 0
        lda EDIT_RE
        sta CURSOR_Y            ; move below the harvested logical line
        lda #CHR_CR
        jsr chrout
        rts

; ----------------------------------------------------------------------------
; harvest_line - read the logical line under the cursor from the overlay into
; EDIT_BUF, trimming trailing spaces. Sets EDIT_LEN, EDIT_IDX, EDIT_RS, EDIT_RE.
; If the input start (EDIT_START_Y) lies within this logical line, harvesting
; starts at the input column so a prompt printed ahead of the cursor is excluded;
; otherwise the whole logical line is taken from column 0 (cursor moved onto
; another line). KCNT/KCNT+1 hold the start row/col scratch.
; ----------------------------------------------------------------------------
harvest_line:
        jsr edit_find_line      ; -> EDIT_RS, EDIT_RE (logical line under the cursor)

        ; Choose start row/col. Default: whole line from column 0.
        lda EDIT_RS
        sta KCNT                ; start row
        stz KCNT+1              ; start col
        ; If EDIT_START_Y is within [rS, rE], start at the input column instead.
        lda EDIT_START_Y
        cmp EDIT_RS
        bcc @addr               ; start_y < rS -> different line
        cmp EDIT_RE
        beq @same
        bcs @addr               ; start_y > rE -> different line
@same:
        lda EDIT_START_Y
        sta KCNT
        lda EDIT_START_X
        sta KCNT+1
@addr:
        jsr overlay_set_rc      ; $B8 -> overlay cell (KCNT row, KCNT+1 col)

        ; count = (rE - startRow)*40 + (40 - startCol), capped at EDIT_BUF_SIZE
        lda EDIT_RE
        sec
        sbc KCNT                ; rE - startRow
        jsr mul40               ; KTMP = (rE - startRow) * 40
        lda #40
        sec
        sbc KCNT+1              ; 40 - startCol  (1..40)
        clc
        adc KTMP
        sta KTMP
        bcc :+
        inc KTMP+1
:       lda KTMP+1              ; cap at EDIT_BUF_SIZE
        bne @cap
        lda KTMP
        cmp #EDIT_BUF_SIZE+1
        bcc @count_ok
@cap:
        lda #EDIT_BUF_SIZE
        sta KTMP
@count_ok:
        ; Read KTMP cells (<= EDIT_BUF_SIZE) from $B8 (auto-stepping), tracking
        ; the last non-space so trailing blanks are trimmed.
        ldx KTMP
        ldy #$00
        stz EDIT_LEN
@read:
        lda IDXA_PORT
        sta EDIT_BUF,y
        cmp #' '
        beq @skip
        tya
        clc
        adc #$01
        sta EDIT_LEN            ; last non-space index + 1
@skip:
        iny
        dex
        bne @read
        stz EDIT_IDX
        rts

; ----------------------------------------------------------------------------
; overlay_set_rc - bind overlay index $B8 and set its address to the cell at
; (KCNT = row, KCNT+1 = col). Clobbers A/X/Y and KTMP.
; ----------------------------------------------------------------------------
overlay_set_rc:
        lda KCNT
        jsr mul40               ; KTMP = row * 40
        lda KTMP
        clc
        adc KCNT+1              ; + col
        sta KTMP
        bcc :+
        inc KTMP+1
:       lda KTMP                ; + overlay nametable base ($10080)
        clc
        adc #OVNT_ADDR_L
        sta KTMP
        lda KTMP+1
        adc #OVNT_ADDR_M
        sta KTMP+1
        lda #VIDX_OVERLAY_NT
        sta IDXA_SELECT
        lda KTMP
        ldx KTMP+1
        ldy #OVNT_ADDR_H
        jsr set_idxa_addr
        rts

; ----------------------------------------------------------------------------
; mul40 - KTMP = A * 40 (A small: row counts <= 24). Clobbers A.
; 40*A = 8 * (5*A); 5*A <= 120 fits 8 bits before the final 3 shifts.
; ----------------------------------------------------------------------------
mul40:
        sta KTMP
        asl
        asl                     ; 4A
        clc
        adc KTMP                ; 5A
        sta KTMP
        stz KTMP+1
        asl KTMP
        rol KTMP+1              ; 10A
        asl KTMP
        rol KTMP+1              ; 20A
        asl KTMP
        rol KTMP+1              ; 40A
        rts

; ----------------------------------------------------------------------------
; edit_find_line - find the logical line under the cursor: EDIT_RS = first row
; (walk up over continuations), EDIT_RE = last row (extend down over them).
; ----------------------------------------------------------------------------
edit_find_line:
        ldx CURSOR_Y
@find_start:
        lda LINE_LINK,x
        bmi @got_start
        dex
        bpl @find_start
        ldx #$00
@got_start:
        stx EDIT_RS
        ldx CURSOR_Y
@find_end:
        cpx #SCR_ROWS-1
        beq @got_end
        inx
        lda LINE_LINK,x
        bpl @find_end           ; continuation: include and keep going
        dex                     ; next row starts a new line: end is the previous
@got_end:
        stx EDIT_RE
        rts

; ----------------------------------------------------------------------------
; Insert/delete operate on the logical line as a contiguous overlay run: read
; it into EDIT_BUF, shift in place, write it back. EDIT_LL is the line's cell
; count (capped at EDIT_BUF_SIZE = two rows, which covers BASIC's 71-char input
; limit); EDIT_CP is the cursor's linear position within the line.
; ----------------------------------------------------------------------------

; edit_line_setup - compute EDIT_LL (capped) and EDIT_CP from EDIT_RS/RE + cursor.
edit_line_setup:
        lda EDIT_RE
        sec
        sbc EDIT_RS             ; rows - 1
        beq @one_row
        lda #EDIT_BUF_SIZE      ; 2+ rows -> cap at two rows
        bra @set_len
@one_row:
        lda #SCR_COLS
@set_len:
        sta EDIT_LL
        lda CURSOR_Y
        sec
        sbc EDIT_RS
        jsr mul40               ; KTMP = (CURSOR_Y - rS) * 40
        lda KTMP
        clc
        adc CURSOR_X
        sta EDIT_CP
        rts

; edit_read_line / edit_write_line - move EDIT_LL cells between the overlay run
; (from row EDIT_RS, column 0) and EDIT_BUF, using $B8's read/write auto-step.
edit_read_line:
        jsr edit_line_addr
        ldx EDIT_LL
        ldy #$00
@r:
        lda IDXA_PORT
        sta EDIT_BUF,y
        iny
        dex
        bne @r
        rts

edit_write_line:
        jsr edit_line_addr
        ldx EDIT_LL
        ldy #$00
@w:
        lda EDIT_BUF,y
        sta IDXA_PORT
        iny
        dex
        bne @w
        rts

edit_line_addr:
        lda EDIT_RS
        sta KCNT
        stz KCNT+1
        jmp overlay_set_rc      ; $B8 -> overlay cell (EDIT_RS, 0)

; edit_cursor_from_cp - place CURSOR_X/Y from EDIT_CP (linear pos, <= two rows).
edit_cursor_from_cp:
        lda EDIT_CP
        cmp #SCR_COLS
        bcc @row0
        sbc #SCR_COLS           ; carry set: A = cp - 40
        sta CURSOR_X
        lda EDIT_RS
        clc
        adc #$01
        sta CURSOR_Y
        rts
@row0:
        sta CURSOR_X
        lda EDIT_RS
        sta CURSOR_Y
        rts

; ----------------------------------------------------------------------------
; edit_delete_left - delete the char left of the cursor and close the gap
; (cursor moves left). No-op at the logical-line start.
; ----------------------------------------------------------------------------
edit_delete_left:
        jsr edit_find_line
        jsr edit_line_setup
        lda EDIT_CP
        beq @done               ; at line start: nothing to delete
        cmp EDIT_LL
        bcs @done               ; out of range (cursor past two-row cap)
        jsr edit_read_line
        ldx EDIT_CP
        dex                     ; X = dest = cp-1
        ldy EDIT_CP             ; Y = src = cp
@shift:
        lda EDIT_BUF,y
        sta EDIT_BUF,x
        inx
        iny
        cpy EDIT_LL
        bne @shift
        lda #' '
        sta EDIT_BUF,x          ; blank the freed last cell
        jsr edit_write_line
        dec EDIT_CP
        jsr edit_cursor_from_cp
@done:
        rts

; ----------------------------------------------------------------------------
; edit_delete_fwd - delete the char at the cursor and close the gap (cursor
; stays). No-op past the end of the line.
; ----------------------------------------------------------------------------
edit_delete_fwd:
        jsr edit_find_line
        jsr edit_line_setup
        lda EDIT_CP
        cmp EDIT_LL
        bcs @done
        jsr edit_read_line
        ldx EDIT_CP             ; X = dest = cp
        ldy EDIT_CP
        iny                     ; Y = src = cp+1
        cpy EDIT_LL
        bcs @blank              ; cursor on the last cell: nothing to pull in
@shift:
        lda EDIT_BUF,y
        sta EDIT_BUF,x
        inx
        iny
        cpy EDIT_LL
        bne @shift
@blank:
        lda #' '
        sta EDIT_BUF,x          ; blank the freed last cell
        jsr edit_write_line
@done:
        rts

; ----------------------------------------------------------------------------
; edit_insert - open a one-cell gap at the cursor, shifting the rest of the line
; right (the last cell falls off). Cursor stays on the new blank.
; ----------------------------------------------------------------------------
edit_insert:
        jsr edit_find_line
        jsr edit_line_setup
        lda EDIT_CP
        cmp EDIT_LL
        bcs @done
        jsr edit_read_line
        ldx EDIT_LL
        dex                     ; X = dest = LL-1 (work backward)
@shift:
        cpx EDIT_CP
        beq @gap
        txa
        tay
        dey                     ; Y = src = X-1
        lda EDIT_BUF,y
        sta EDIT_BUF,x
        dex
        bra @shift
@gap:
        lda #' '
        sta EDIT_BUF,x          ; blank at the cursor (X == cp)
        jsr edit_write_line
@done:
        rts

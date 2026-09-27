; Full 256 KiB MIA RAM, distinct from CPU PEEK/POKE and external banked RAM.
.setcpu "65C02"
.import mia_mem_read, mia_mem_write, mia_mem_copy, mia_mem_fill
.import mia_mem_rect, mia_mem_fill_rect
.import km_src, km_dst, km_count, km_value
.import km_rows, km_sstride, km_dstride

; Nonzero while MCOPY/MFILL parse their rectangle form. Statements can't nest,
; so nothing else touches it between parsing and the copy.
mem_rect: .byte 0

; Convert the numeric FAC to a nonnegative 24-bit integer; fractions truncate.
mem_integer24:
        jsr CHKNUM
        lda FACSIGN
        jmi IQERR
        lda FAC
        cmp #$99
        jcs IQERR
        jmp QINT
; Return A:X:Y = low:middle:high, with all address bits checked before masking.
mem_address:
        jsr mem_integer24
        lda FAC+2
        cmp #4
        jcs IQERR
        bra mem_result
mem_length:
        jsr mem_integer24
        lda FAC+2
        cmp #4
        bcc mem_result
        jne IQERR
        lda FAC+3
        ora FAC+4
        jne IQERR                ; maximum count is exactly $40000
mem_result:
        ldy FAC+2
        ldx FAC+3
        lda FAC+4
        rts

BASIC_MPEEK:
        jsr mem_address          ; extension dispatch evaluated (address)
        sta km_src
        stx km_src+1
        sty km_src+2
        jsr mia_mem_read
        tay
        jmp SNGFLT

BASIC_MPOKE:
        jsr FRMNUM
        jsr mem_address
        pha
        phx
        phy
        jsr COMBYTE
        stx km_value
        ply
        sty km_dst+2
        plx
        stx km_dst+1
        pla
        sta km_dst
        jmp mia_mem_write

; ",n" -> A:X = n, 0-65535.
mem_word_arg:
        jsr CHKCOM
        jsr FRMNUM
        jsr GETADR
        lda LINNUM
        ldx LINNUM+1
        rts
; ",rows" -> km_rows, and mark the statement as the rectangle form.
mem_rect_rows:
        jsr mem_word_arg
        sta km_rows
        stx km_rows+1
        lda #1
        sta mem_rect
        rts

; Keep earlier arguments on the CPU stack during expression evaluation:
; nested MPEEK calls use the same kernel scratch and must not overwrite them.
; km_count, km_rows and the strides are safe: MPEEK only writes km_src.
;
; MCOPY src, dst, len[, rows, srcstride, dststride]: with rows, copy rows of
; len bytes, each row starting srcstride (dststride) bytes after the last.
BASIC_MCOPY:
        jsr FRMNUM
        jsr mem_address
        pha
        phx
        phy
        jsr CHKCOM
        jsr FRMNUM
        jsr mem_address
        pha
        phx
        phy
        jsr CHKCOM
        jsr FRMNUM
        jsr mem_length
        sta km_count
        stx km_count+1
        sty km_count+2
        stz mem_rect
        jsr CHRGOT
        cmp #','
        bne @pop
        jsr mem_rect_rows
        jsr mem_word_arg
        sta km_sstride
        stx km_sstride+1
        jsr mem_word_arg
        sta km_dstride
        stx km_dstride+1
@pop:   ply
        sty km_dst+2
        plx
        stx km_dst+1
        pla
        sta km_dst
        ply
        sty km_src+2
        plx
        stx km_src+1
        pla
        sta km_src
        lda mem_rect
        bne @rect
        jsr mia_mem_copy
        jcc IQERR
        rts
@rect:  jsr mia_mem_rect
        jcc IQERR
        rts

; MFILL addr, len, value[, rows, stride]: with rows, fill rows of len bytes,
; each row starting stride bytes after the last.
BASIC_MFILL:
        jsr FRMNUM
        jsr mem_address
        pha
        phx
        phy
        jsr CHKCOM
        jsr FRMNUM
        jsr mem_length
        pha
        phx
        phy
        jsr COMBYTE
        stx km_value
        stz mem_rect
        jsr CHRGOT
        cmp #','
        bne @pop
        jsr mem_rect_rows
        jsr mem_word_arg
        sta km_dstride
        stx km_dstride+1
@pop:   ply
        sty km_count+2
        plx
        stx km_count+1
        pla
        sta km_count
        ply
        sty km_dst+2
        plx
        stx km_dst+1
        pla
        sta km_dst
        lda mem_rect
        bne @rect
        jsr mia_mem_fill
        jcc IQERR
        rts
@rect:  jsr mia_mem_fill_rect
        jcc IQERR
        rts

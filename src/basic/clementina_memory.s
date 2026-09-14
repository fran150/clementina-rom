; Full 256 KiB MIA RAM, distinct from CPU PEEK/POKE and external banked RAM.
.setcpu "65C02"
.import mia_mem_read, mia_mem_write, mia_mem_copy, mia_mem_fill
.import km_src, km_dst, km_count, km_value

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

; Keep earlier arguments on the CPU stack during expression evaluation:
; nested MPEEK calls use the same kernel scratch and must not overwrite them.
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
        ply
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
        jsr mia_mem_copy
        jcc IQERR
        rts

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
        ply
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
        jsr mia_mem_fill
        jcc IQERR
        rts

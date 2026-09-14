; TI is a numeric system variable (60 Hz, wraps at 24 hours). TICKS(0) is a
; separate monotonic millisecond clock modulo 2^32. Both use MIA wall time.
.setcpu "65C02"
.import timing_read, timing_set, ktime_snapshot

; Recognize the numeric scalar TI (including longer names with the same two
; significant letters, as in MS BASIC). Typed variables/arrays are distinct.
; C=1 consumes the name; C=0 leaves TXTPTR untouched. A/X/Y are scratch.
basic_is_ti:
        ldy #0
        lda (TXTPTR),y
        cmp #'T'
        bne @no
        iny
        lda (TXTPTR),y
        cmp #'I'
        bne @no
@next:  iny
        lda (TXTPTR),y
        cmp #'0'
        bcc @end
        cmp #':'
        bcc @next
        cmp #'A'
        bcc @end
        cmp #'Z'+1
        bcc @next
@end:   cmp #' '
        bne @suffix
        iny
        lda (TXTPTR),y
        bra @end
@suffix:
        cmp #'$'
        beq @no
        cmp #'%'
        beq @no
        cmp #'('
        beq @no
@yes:   tya
        clc
        adc TXTPTR
        sta TXTPTR
        bcc @got
        inc TXTPTR+1
@got:   jsr CHRGOT
        sec
        rts
@no:    jsr CHRGOT
        clc
        rts

basic_clock_read:
        jsr timing_read
        jcc IQERR                ; old firmware has no version-1 snapshot
        rts

BASIC_TICKS:
        jsr CONINT
        cpx #0
        jne IQERR
        jsr basic_clock_read
        lda ktime_snapshot+3
        sta FAC+1
        lda ktime_snapshot+2
        sta FAC+2
        lda ktime_snapshot+1
        sta FAC+3
        lda ktime_snapshot
        sta FAC+4
        bra timing_float_u32

BASIC_TI:
        jsr basic_clock_read
        stz FAC+1
        lda ktime_snapshot+6
        sta FAC+2
        lda ktime_snapshot+5
        sta FAC+3
        lda ktime_snapshot+4
        sta FAC+4
; Float an unsigned big-endian integer in FAC+1..4 without a signed conversion.
timing_float_u32:
        lda #$A0
        sta FAC
        stz FACSIGN
        stz FACEXTENSION
        stz VALTYP
        jmp NORMALIZE_FAC2

BASIC_SET_TI:
        lda #TOKEN_EQUAL
        jsr SYNCHR
        jsr FRMNUM
        lda FACSIGN
        jmi IQERR
        lda FAC
        cmp #$99
        jcs IQERR
        jsr QINT
        lda FAC+2
        cmp #$4F
        bcc @valid
        jne IQERR
        lda FAC+3
        cmp #$1A
        jcs IQERR                ; valid range 0..$4F19FF = 5,183,999
@valid: lda FAC+2
        pha
        lda FAC+3
        pha
        lda FAC+4
        pha
        jsr basic_clock_read    ; require clock support before changing it
        pla
        sta ktime_snapshot+4
        pla
        sta ktime_snapshot+5
        pla
        sta ktime_snapshot+6
        jmp timing_set

BASIC_DELAY:
        jsr FRMNUM
        jsr GETADR              ; 0..65535 ms, usual BASIC truncation
        lda LINNUM
        sta delay_ms
        lda LINNUM+1
        sta delay_ms+1
        ora delay_ms
        beq @done
        jsr basic_clock_read
        ldx #3
@start: lda ktime_snapshot,x
        sta delay_start,x
        dex
        bpl @start
@wait:  jsr ISCNTC               ; normal BREAK path also stops background PLAY
        jsr basic_clock_read
        sec
        lda ktime_snapshot
        sbc delay_start
        sta delay_elapsed
        lda ktime_snapshot+1
        sbc delay_start+1
        sta delay_elapsed+1
        lda ktime_snapshot+2
        sbc delay_start+2
        sta delay_elapsed+2
        lda ktime_snapshot+3
        sbc delay_start+3
        ora delay_elapsed+2
        bne @done               ; unsigned elapsed >= 65536
        lda delay_elapsed+1
        cmp delay_ms+1
        bcc @wait
        bne @done
        lda delay_elapsed
        cmp delay_ms
        bcc @wait
@done:  rts

delay_ms: .res 2,0
delay_start: .res 4,0
delay_elapsed: .res 3,0

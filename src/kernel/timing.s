; MIA clock protocol (sys/timing.h): latch $11078..$1107F with command $55.
; No periodic MIA writer touches the snapshot. The existing VIA tick/IRQ is
; independent and continues servicing background PLAY while callers wait.
.segment "KERNCODE"
.export timing_read, timing_set, ktime_snapshot

timing_read:
        lda #$55
        ldx #0
        ldy #0
        jsr input_command
        ldx #0
@read:  txa
        clc
        adc #$78
        jsr input_read_byte
        sta ktime_snapshot,x
        inx
        cpx #8
        bne @read
        lda ktime_snapshot+7
        cmp #1                  ; C=1/Z=1 on supported protocol
        beq @ok
        clc
        rts
@ok:    sec
        rts

; Set TI from the little-endian three-byte snapshot TI slot. Foreground only.
timing_set:
@wait:  lda STATUS_L
        and #MIA_STAT_CMD_RUNNING
        bne @wait
        lda ktime_snapshot+4
        sta CMD_PARAM1
        lda ktime_snapshot+5
        sta CMD_PARAM2
        lda ktime_snapshot+6
        sta CMD_PARAM3
        lda #$56
        sta CMD_TRIGGER
@done:  lda STATUS_L
        and #MIA_STAT_CMD_RUNNING
        bne @done
        rts

ktime_snapshot: .res 8,0         ; ms32, TI24, version

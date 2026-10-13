; MIA clock protocol (sys/timing.h): latch $11078..$1107F with command $55.
; No periodic MIA writer touches the snapshot. The existing VIA tick/IRQ is
; independent and keeps running while callers wait. The CPU-side copy is
; CLOCK_SNAPSHOT ($02F8-$02FF, kernel.inc), a fixed address programs read
; after KERN_RDTIM; BASIC's TI/TICKS/DELAY use it through ktime_snapshot.
.segment "KERNCODE"
.export timing_read, timing_set, ktime_snapshot

ktime_snapshot = CLOCK_SNAPSHOT  ; ms32, 60 Hz count24, version

; timing_read - KERN_RDTIM. Copies MIA's clock snapshot to CLOCK_SNAPSHOT.
; Returns C=1 if MIA filled it (CLOCK_VERSION = 1), C=0 on firmware without
; the clock. Clobbers A/X/Y. Foreground only.
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

; settim - KERN_SETTIM. Sets MIA's 60 Hz clock from A (low), X (mid) and
; Y (high). MIA ignores values of 5,184,000 (24 hours) or more. The value is
; also left in CLOCK_60HZ. Foreground only.
settim:
        sta ktime_snapshot+4
        stx ktime_snapshot+5
        sty ktime_snapshot+6
        ; fall through
; Set the 60 Hz clock from the snapshot's three-byte slot. Foreground only.
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


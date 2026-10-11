; ============================================================================
; input.s - keyboard input from the MIA FIFO, the keyboard queue and KERN_STOP
; ----------------------------------------------------------------------------
; Included by kernel.s into the single kernel translation unit (after
; kernel.inc).
; ============================================================================

.segment "KERNCODE"

; ----------------------------------------------------------------------------
; chrin - blocking read of one text byte from the MIA FIFO -> A
; Records LAST_KEY for easy verification in the emulator's memory window before
; the video client is attached.
; ----------------------------------------------------------------------------
chrin:
        jsr cursor_show
        lda #CURSOR_BLINK_TICKS
        sta CURSOR_BLINK_COUNT
        lda #$01
        sta CURSOR_BLINK_ACTIVE
@wait:
        jsr getkey_nb
        bcc @wait               ; nothing yet, keep polling
        sta KCHR
        php
        sei
        stz CURSOR_BLINK_ACTIVE
        jsr cursor_hide
        plp
        lda KCHR
        sta LAST_KEY
        rts

; ----------------------------------------------------------------------------
; getkey_nb - non-blocking read. Returns C=1 and A=char if available, else C=0.
; Keys KERN_STOP queued come first, then the MIA FIFO. Preserves X/Y.
; ----------------------------------------------------------------------------
getkey_nb:
        lda KEYQ_LEN
        bne keyq_pop
        lda INPUT_STATUS
        and #INPUT_STATUS_TEXT_READY
        beq @none
        lda INPUT_CHAR
        sec
        rts
@none:
        clc
        rts

; ----------------------------------------------------------------------------
; keyq_pop - remove the oldest queued key. Returns C=1 and A=key. Preserves X/Y.
; Only called with KEYQ_LEN nonzero.
; ----------------------------------------------------------------------------
keyq_pop:
        phx
        lda KEYQ
        pha
        ldx #$00
@shift: lda KEYQ+1,x
        sta KEYQ,x
        inx
        cpx #KEYQ_SIZE-1
        bne @shift
        dec KEYQ_LEN
        pla
        plx
        sec
        rts

; ----------------------------------------------------------------------------
; stop - KERN_STOP: has the user typed Ctrl-C (break)? Z=1 if so.
; Drains the MIA text FIFO, queueing every other key in KEYQ for getkey_nb,
; so checking for a break never loses typed keys. On a break the queue is
; emptied and the routine returns A=KEY_BREAK with Z=1 and C=1, the flags
; BASIC's STOP statement expects when ISCNTC falls into it. Otherwise Z=0.
; Clobbers A/X.
; ----------------------------------------------------------------------------
stop:
        lda INPUT_STATUS
        and #INPUT_STATUS_TEXT_READY
        beq @nobreak
        lda INPUT_CHAR
        cmp #KEY_BREAK
        beq @break
        ldx KEYQ_LEN
        cpx #KEYQ_SIZE
        bcs stop                ; queue full: drop the key, keep looking
        sta KEYQ,x
        inc KEYQ_LEN
        bra stop
@break: stz KEYQ_LEN            ; flags still Z=1, C=1 from the cmp
        rts
@nobreak:
        lda #$01                ; Z=0 -> no break
        rts

; Indexed input services are link exports; the fixed public jump table is full.
; A = input-block offset ($00-$7F), returns A = byte, preserves X/Y.
; Explicit seek is essential: selecting a descriptor does not rewind it.
.export input_read_byte, input_clear_text, input_command
input_read_byte:
        php
        sei
        pha
        lda #$60
        sta IDXA_SELECT
        lda #CFG_IDXA_ADDR_H
        sta CFG_SELECT
        lda #$01
        sta CFG_PORT
        lda #CFG_IDXA_ADDR_M
        sta CFG_SELECT
        lda #$10
        sta CFG_PORT
        lda #CFG_IDXA_ADDR_L
        sta CFG_SELECT
        pla
        sta CFG_PORT
        lda IDXA_PORT
        plp
        rts

; Drain the currently queued bytes (KEYQ and the FIFO); bounded even if new
; input keeps arriving.
input_clear_text:
        stz KEYQ_LEN
        ldx INPUT_CHAR_COUNT
        beq @done
@next:  lda INPUT_CHAR
        dex
        bne @next
@done:  rts

; A=command, X/Y=parameters 1/2; parameter 3 is zero.
; Foreground-only, uses the normal synchronous MIA command handshake.
input_command:
        pha
@wait:  lda STATUS_L
        and #MIA_STAT_CMD_RUNNING
        bne @wait
        stx CMD_PARAM1
        sty CMD_PARAM2
        stz CMD_PARAM3
        pla
        sta CMD_TRIGGER
@done:  lda STATUS_L
        and #MIA_STAT_CMD_RUNNING
        bne @done
        rts

; ============================================================================
; input.s - keyboard input from the MIA FIFO and the ISCNTC (break) hook
; ----------------------------------------------------------------------------
; Included by kernel.s into the single kernel translation unit (after
; kernel.inc).
; ============================================================================

.segment "CODE"

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
; ----------------------------------------------------------------------------
getkey_nb:
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
; stop - ISCNTC: report whether a Ctrl-C (break) is pending. Z=1 if break.
; Milestone-1 placeholder: never reports a break. Real break handling lands
; with BASIC.
; ----------------------------------------------------------------------------
stop:
        lda #$01                ; Z=0 -> "no break"
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

; Drain the currently queued bytes; bounded even if new input keeps arriving.
input_clear_text:
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

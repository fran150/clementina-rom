; ============================================================================
; input.s - keyboard input from the MIA FIFO and the ISCNTC (break) hook
; ----------------------------------------------------------------------------
; Included by kernel.s into the single kernel translation unit (after
; kernel.inc).
; ============================================================================

.segment "CODE"

; ----------------------------------------------------------------------------
; chrin - blocking read of one text byte from the MIA FIFO -> A
; Records LAST_KEY / KEY_COUNT for easy verification in the emulator's memory
; window before the video client is attached.
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
        inc KEY_COUNT
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

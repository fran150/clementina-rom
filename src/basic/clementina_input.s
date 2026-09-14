.setcpu "65C02"
; BASIC input front end. MIA layout: firmware src/mia/input/input.h.
; State is in the writable loaded image, outside BASIC's movable heap.
.import input_read_byte, input_clear_text, input_command

basic_input_reset:
        ldx #input_data_end-input_data-1
@loop:  stz input_data,x
        dex
        bpl @loop
        rts

BASIC_KEYCLEAR:
        jmp input_clear_text

BASIC_INPUTMODE:
        jsr GETBYT
        cpx #3
        jcs IQERR
        phx
        ldy #0
        lda #$50
        jsr input_command
        plx
        lda input_source_bits,x
        and $FFF2
        jeq IQERR                 ; requested source unavailable
        jmp basic_input_reset
input_source_bits: .byte $20,$40,$80

; Delay/interval are 16-bit milliseconds. Configure interval before enabling.
BASIC_KEYREPEAT:
        jsr FRMNUM
        jsr GETADR
        lda LINNUM
        ora LINNUM+1
        bne @timing
        jsr CHRGOT
        cmp #','
        jeq IQERR
        ldx #0
        ldy #0
        lda #$52
        jmp input_command
@timing:
        lda LINNUM
        pha
        lda LINNUM+1
        pha
        jsr CHKCOM
        jsr FRMNUM
        jsr GETADR
        lda LINNUM
        ora LINNUM+1
        jeq IQERR
        ldx LINNUM
        ldy LINNUM+1
        lda #$53
        jsr input_command
        ply
        plx
        lda #$52
        jmp input_command

BASIC_KEYRPT:
        jsr GETBYT
        phx
        jsr COMBYTE
        cpx #2
        jcs IQERR
        txa
        tay
        plx
        lda #$54
        jmp input_command

BASIC_KEYDOWN:
        jsr CONINT
        lda #0
        bra input_key
BASIC_CONSDOWN:
        jsr CONINT
        lda #$20
input_key:
        sta input_offset
        txa
        and #7
        tay
        txa
        lsr
        lsr
        lsr
        clc
        adc input_offset
        jsr input_read_byte
        and CHR_BIT_TABLE,y
input_boolean:
        ldy #0
        cmp #0
        beq input_unsigned
        iny
input_unsigned:
        lda #0
        jmp GIVAYF
input_signed:
        tay
        lda #0
        cpy #$80
        bcc @positive
        lda #$FF
@positive:
        jmp GIVAYF

BASIC_INPUTDEV:
        jsr CONINT
        cpx #0
        jne IQERR
        lda #$45
        jsr input_read_byte
        tay
        bra input_unsigned

; Slot offset = 10*n. All queries read the last explicit PADREAD sample.
input_slot:
        jsr CONINT
        cpx #4
        jcs IQERR
        txa
        asl
        sta input_offset
        asl
        asl
        clc
        adc input_offset
        tax
        rts
BASIC_PADREAD:
        jsr FRMNUM
        jsr input_slot
        ldy #10
@next:  txa
        clc
        adc #$50
        jsr input_read_byte
        sta input_pads,x
        inx
        dey
        bne @next
        rts
BASIC_PADON:
        jsr input_slot
        lda input_pads,x
        and #$80
        bra input_boolean
BASIC_PADDIR:
        jsr input_slot
        lda input_pads,x
        and #$0F
        tay
        bra input_unsigned
BASIC_PADSTICK:
        jsr input_slot
        ldy input_pads+1,x
        bra input_unsigned

; Two-argument functions enter with TXTPTR at '(' (see dispatch).
; Keep the slot on the CPU stack so nested function arguments cannot overwrite it.
input_pad_pair:
        jsr CHKOPN
        jsr FRMNUM
        jsr input_slot
        phx
        jsr COMBYTE
        phx
        jsr CHKCLS
        ply                         ; selector
        plx                         ; slot offset
        rts
BASIC_PADBTN:
        jsr input_pad_pair
        cpy #16
        jcs IQERR
        tya
        and #7
        pha
        cpy #8
        bcc @first
        inx
@first: lda input_pads+2,x
        ply
        and CHR_BIT_TABLE,y
        jmp input_boolean
BASIC_PADAXIS:
        jsr input_pad_pair
        cpy #4
        jcs IQERR
        sty input_offset
        txa
        clc
        adc input_offset
        tax
        lda input_pads+4,x
        jmp input_signed
BASIC_PADTRIG:
        jsr input_pad_pair
        cpy #2
        jcs IQERR
        sty input_offset
        txa
        clc
        adc input_offset
        tax
        ldy input_pads+8,x
        jmp input_unsigned

; Relative mouse deltas are signed modulo-256 differences. Source/capability
; transitions observed between calls invalidate the baseline. The transport
; has no session generation counter, so an unobserved reconnect cannot be detected.
BASIC_MOUSE:
        lda $FFF2
        and #$E0
        sta input_offset
        lda #$45
        jsr input_read_byte
        and #4
        ora input_offset
        cmp input_mouse_source
        beq @same
        sta input_mouse_source
        stz input_mouse_valid
@same:  and #4
        bne @sample
        stz input_mouse_valid
@sample:
        ldx #0
@read:  txa
        clc
        adc #$40
        jsr input_read_byte
        sta input_mouse_now,x
        inx
        cpx #5
        bne @read
        ldx #4
@delta: lda input_mouse_now,x
        sec
        sbc input_mouse_prev-1,x
        ldy input_mouse_valid
        bne @have
        lda #0
@have:  sta input_mouse_delta-1,x
        lda input_mouse_now,x
        sta input_mouse_prev-1,x
        dex
        bne @delta
        lda input_mouse_source
        and #4
        sta input_mouse_valid
        ; Order: DX,DY,BUTTONS,WHEEL,PAN.
        ldx #0
@store: phx
        lda input_mouse_order,x
        tax
        lda input_mouse_delta,x
        cpx #4
        bne @signed
        lda input_mouse_now
        and #$1F
        jsr mia_store_byte
        bra @stored
@signed:
        jsr input_store_signed
@stored:
        plx
        inx
        cpx #5
        beq @done
        phx
        jsr CHKCOM
        plx
        bra @store
@done:  rts
input_mouse_order: .byte 0,1,4,2,3

input_store_signed:
        pha
        jsr PTRGET
        bit VALTYP
        jmi mia_typerr
        sta FORPNT
        sty FORPNT+1
        pla
        jsr input_signed
        lda VALTYP+1
        bpl @float
        jsr ROUND_FAC
        jsr AYINT
        ldy #0
        lda FAC+3
        sta (FORPNT),y
        iny
        lda FAC+4
        sta (FORPNT),y
        rts
@float: jmp SETFOR

input_data:
input_offset:       .byte 0
input_pads:         .res 40,0
input_mouse_source: .byte 0
input_mouse_valid:  .byte 0
input_mouse_now:    .res 5,0
input_mouse_prev:   .res 4,0
input_mouse_delta:  .res 4,0
input_data_end:

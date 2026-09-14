; Filesystem extensions. Firmware SD protocol v6 adds FS_FILE_INFO ($89).
MIA_CMD_FS_SYNC = $80
MIA_CMD_FS_STAT = $82
MIA_CMD_FS_GET_FREE = $86
MIA_CMD_FS_FILE_INFO = $89

fs_command:
        jsr mia_sd_cmd
        jne mia_fileerr
        rts

; Nonnegative unsigned 32-bit FAC -> big endian FAC+1..4.
; At exponent $A0 the 32-bit mantissa is already the desired integer;
; QINT's signed conversion would discard its top bit.
fs_integer32:
        jsr CHKNUM
        lda FACSIGN
        jmi IQERR
        lda FAC
        cmp #$A1
        jcs IQERR
        cmp #$A0
        beq @done
        jmp QINT
@done:  rts

BASIC_FLUSH:
        lda #'#'
        jsr SYNCHR
        jsr GETBYT
        dex
        cpx #16
        jcs IQERR
        jsr mia_sd_select_handle
        lda #MIA_CMD_FS_SYNC
        jmp fs_command

BASIC_FPOS:
        lda #$1C
        bra fs_file_info
BASIC_FSIZE:
        lda #$18
fs_file_info:
        pha
        jsr CONINT
        dex
        cpx #16
        jcs IQERR
        jsr mia_sd_select_handle
        ; Old firmware must not return stale data for an unknown command.
        lda #0
        jsr mia_sd_seek
        lda IDXA_PORT
        cmp #6
        jcc mia_fileerr
        lda #MIA_CMD_FS_FILE_INFO
        jsr fs_command
        pla
        jsr mia_sd_seek
fs_read_u32:
        lda IDXA_PORT
        sta FAC+4
        lda IDXA_PORT
        sta FAC+3
        lda IDXA_PORT
        sta FAC+2
        lda IDXA_PORT
        sta FAC+1
        jmp timing_float_u32

BASIC_DISKFREE:
        jsr CONINT
        cpx #0
        jne IQERR
        lda #MIA_CMD_FS_GET_FREE
        jsr fs_command
        lda #$28
        jsr mia_sd_seek
        ldy IDXA_PORT
        lda IDXA_PORT
        jsr GIVAYF
        ldx #<fs_factor
        ldy #>fs_factor
        jsr STORE_FAC_AT_YX_ROUNDED
        lda #$20
        jsr mia_sd_seek
        jsr fs_read_u32
        lda #<fs_factor
        ldy #>fs_factor
        jsr FMULT
        ; Multiply by 512 without overflowing a 32-bit integer temporary.
        lda FAC
        beq @done
        clc
        adc #9
        sta FAC
@done:  rts
fs_factor: .res 5,0

BASIC_FSTAT:
        jsr mia_parse_path_expr
        lda #MIA_CMD_FS_STAT
        jsr fs_command
        jsr mia_sd_select_dir_entry
        ldx #0
@read:  lda IDXA_PORT
        sta fs_metadata,x
        inx
        cpx #12
        bne @read
        ldx #0
@store: phx
        jsr CHKCOM
        jsr PTRGET
        bit VALTYP
        jmi mia_typerr
        sta FORPNT
        sty FORPNT+1
        plx
        phx
        lda VALTYP+1
        pha
        lda fs_meta_offsets,x
        tay
        stz FAC+1
        stz FAC+2
        stz FAC+3
        lda fs_metadata,y
        sta FAC+4
        cpx #1
        beq @float
        lda fs_metadata+1,y
        sta FAC+3
        cpx #0
        bne @float
        lda fs_metadata+2,y
        sta FAC+2
        lda fs_metadata+3,y
        sta FAC+1
@float: jsr timing_float_u32
        pla
        bpl @real
        jsr ROUND_FAC
        jsr AYINT
        ldy #0
        lda FAC+3
        sta (FORPNT),y
        iny
        lda FAC+4
        sta (FORPNT),y
        bra @next
@real:  jsr SETFOR
@next:  plx
        inx
        cpx #4
        bne @store
        rts
fs_meta_offsets: .byte 4,0,8,10
fs_metadata: .res 12,0

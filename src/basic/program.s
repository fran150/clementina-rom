; error
; line input, line editing
; tokenize
; detokenize
; BASIC program memory management

; MICROTAN has some nonstandard extension to LIST here

.segment "CODE"

MEMERR:
        ldx     #ERR_MEMFULL

; ----------------------------------------------------------------------------
; HANDLE AN ERROR
;
; (X)=OFFSET IN ERROR MESSAGE TABLE
; (ERRFLG) > 128 IF "ON ERR" TURNED ON
; (CURLIN+1) = $FF IF IN DIRECT MODE
; ----------------------------------------------------------------------------
ERROR:
        lsr     Z14
.ifdef CONFIG_FILE
        lda     CURDVC    ; output
        beq     LC366     ; is screen
        jsr     CLRCH     ; otherwise redirect output back to screen
        lda     #$00
        sta     CURDVC
LC366:
.endif
.ifdef STYLED_STRINGS
        lda     BASIC_DEFAULT_ATTR   ; the whole error line (?<name> ERROR) prints in
        sta     TEXT_ATTR            ; the BASIC pen. OUTQUES/OUTDO print '?'<name> at
.endif                               ; the live pen, so set it here; edit_line reasserts
                                     ; the editor pen for the cursor afterward.
        jsr     CRDO
        jsr     OUTQUES
L2329:
        lda     ERROR_MESSAGES,x
.ifndef CONFIG_SMALL_ERROR
        pha
        and     #$7F
.endif
        jsr     OUTDO
.ifdef CONFIG_SMALL_ERROR
        lda     ERROR_MESSAGES+1,x
  .ifdef KBD
        and     #$7F
  .endif
        jsr     OUTDO
.else
        inx
        pla
        bpl     L2329
.endif
        jsr     STKINI
        lda     #<QT_ERROR
        ldy     #>QT_ERROR

; ----------------------------------------------------------------------------
; PRINT STRING AT (Y,A)
; PRINT CURRENT LINE # UNLESS IN DIRECT MODE
; FALL INTO WARM RESTART
; ----------------------------------------------------------------------------
PRINT_ERROR_LINNUM:
        jsr     STROUT
        ldy     CURLIN+1
        iny
        beq     RESTART
        jsr     INPRT

; ----------------------------------------------------------------------------
; WARM RESTART ENTRY
; ----------------------------------------------------------------------------
RESTART:
.ifdef KBD
        jsr     CRDO
        nop
L2351X:
        jsr     OKPRT
L2351:
        jsr     INLIN
LE28E:
        bpl     RESTART
.else
        lsr     Z14
 .ifndef AIM65
        lda     #<QT_OK
        ldy     #>QT_OK
  .ifdef CONFIG_CBM_ALL
        jsr     STROUT
  .else
        jsr     GOSTROUT
  .endif
 .else
        jsr     GORESTART
 .endif
L2351:
        jsr     INLIN
.endif
        stx     TXTPTR
        sty     TXTPTR+1
        jsr     CHRGET
.ifdef CONFIG_11
; bug in pre-1.1: CHRGET sets Z on '\0'
; and ':' - a line starting with ':' in
; direct mode gets ignored
        tax
.endif
.ifdef KBD
        beq     L2351X
.else
        beq     L2351
.endif
        ldx     #$FF
        stx     CURLIN+1
        bcc     NUMBERED_LINE
        jsr     PARSE_INPUT_LINE
        jmp     NEWSTT2

; ----------------------------------------------------------------------------
; HANDLE NUMBERED LINE
; ----------------------------------------------------------------------------
NUMBERED_LINE:
        jsr     LINGET
        jsr     PARSE_INPUT_LINE
        sty     EOLPNTR
.ifdef STYLED_STRINGS
        sty     STYLE_BASE_LEN  ; base stored-line length before any sidecar
        jsr     style_side_extend_eolpntr
.endif
.ifdef KBD
        jsr     FNDLIN2
        lda     JMPADRS+1
        sta     LOWTR
        sta     Z96
        lda     JMPADRS+2
        sta     LOWTR+1
        sta     Z96+1
        lda     LINNUM
        sta     L06FE
        lda     LINNUM+1
        sta     L06FE+1
        inc     LINNUM
        bne     LE2D2
        inc     LINNUM+1
        bne     LE2D2
        jmp     SYNERR
LE2D2:
        jsr     LF457
        ldx     #Z96
        jsr     CMPJMPADRS
        bcs     LE2FD
LE2DC:
        ldx     #$00
        lda     (JMPADRS+1,x)
        sta     (Z96,x)
        inc     JMPADRS+1
        bne     LE2E8
        inc     JMPADRS+2
LE2E8:
        inc     Z96
        bne     LE2EE
        inc     Z96+1
LE2EE:
        ldx     #VARTAB
        jsr     CMPJMPADRS
        bne     LE2DC
        lda     Z96
        sta     VARTAB
        lda     Z96+1
        sta     VARTAB+1
LE2FD:
        jsr     SETPTRS
        jsr     LE33D
        lda     INPUTBUFFER
LE306:
        beq     LE28E
        cmp     #$A5
        beq     LE306
        clc
.else
        jsr     FNDLIN
        bcc     PUT_NEW_LINE
        ldy     #$01
        lda     (LOWTR),y
        sta     INDEX+1
        lda     VARTAB
        sta     INDEX
        lda     LOWTR+1
        sta     DEST+1
        lda     LOWTR
        dey
        sbc     (LOWTR),y
        clc
        adc     VARTAB
        sta     VARTAB
        sta     DEST
        lda     VARTAB+1
        adc     #$FF
        sta     VARTAB+1
        sbc     LOWTR+1
        tax
        sec
        lda     LOWTR
        sbc     VARTAB
        tay
        bcs     L23A5
        inx
        dec     DEST+1
L23A5:
        clc
        adc     INDEX
        bcc     L23AD
        dec     INDEX+1
        clc
L23AD:
        lda     (INDEX),y
        sta     (DEST),y
        iny
        bne     L23AD
        inc     INDEX+1
        inc     DEST+1
        dex
        bne     L23AD
.endif
; ----------------------------------------------------------------------------
PUT_NEW_LINE:
.ifndef KBD
  .ifdef CONFIG_2
        jsr     SETPTRS
        jsr     LE33D
        lda     INPUTBUFFER
        beq     L2351
        clc
  .else
        lda     INPUTBUFFER
        beq     FIX_LINKS
        lda     MEMSIZ
        ldy     MEMSIZ+1
        sta     FRETOP
        sty     FRETOP+1
  .endif
.endif
        lda     VARTAB
        sta     HIGHTR
        adc     EOLPNTR
        sta     HIGHDS
        ldy     VARTAB+1
        sty     HIGHTR+1
        bcc     L23D6
        iny
L23D6:
        sty     HIGHDS+1
        jsr     BLTU
.ifdef CONFIG_INPUTBUFFER_0200
        lda     LINNUM
        ldy     LINNUM+1
        sta     INPUTBUFFER-2
        sty     INPUTBUFFER-1
.endif
        lda     STREND
        ldy     STREND+1
        sta     VARTAB
        sty     VARTAB+1
.ifdef STYLED_STRINGS
        ldy     STYLE_BASE_LEN
.else
        ldy     EOLPNTR
.endif
        dey
; ---COPY LINE INTO PROGRAM-------
L23E6:
        lda     INPUTBUFFER-4,y
        sta     (LOWTR),y
        dey
        bpl     L23E6
.ifdef STYLED_STRINGS
        jsr     style_side_copy_to_program
.endif

; ----------------------------------------------------------------------------
; CLEAR ALL VARIABLES
; RE-ESTABLISH ALL FORWARD LINKS
; ----------------------------------------------------------------------------
FIX_LINKS:
        jsr     SETPTRS
.ifdef CONFIG_2
        jsr     LE33D
        jmp     L2351
LE33D:
.endif
        lda     TXTTAB
        ldy     TXTTAB+1
        sta     INDEX
        sty     INDEX+1
        clc
L23FA:
        ldy     #$01
        lda     (INDEX),y
.ifdef CONFIG_2
        beq     RET3
.else
        jeq     L2351
.endif
        ldy     #$04
L2405:
        iny
        lda     (INDEX),y
        bne     L2405
        iny
.ifdef STYLED_STRINGS
        jsr     style_skip_sidecar_at_index_y
.endif
        tya
        adc     INDEX
        tax
        ldy     #$00
        sta     (INDEX),y
        lda     INDEX+1
        adc     #$00
        iny
        sta     (INDEX),y
        stx     INDEX
        sta     INDEX+1
        bcc     L23FA	; always

; ----------------------------------------------------------------------------
.ifdef KBD
.include "kbd_loadsave.s"
.endif

.ifdef CONFIG_2
; !!! kbd_loadsave.s requires an RTS here!
RET3:
		rts
.endif

.ifdef STYLED_STRINGS
; ----------------------------------------------------------------------------
; Program-line style sidecars
;
; While tokenizing a numbered line, quoted literal contents are copied from the
; screen-edited input buffer to the tokenized output. At that moment X is still
; the original input address (so EDIT_ATTR_BUF + (X-INPUTBUFFER) is the visible
; style), and Y is the tokenized output position. We capture compact records in
; STYLE_SIDE_BUF and append them after the stored line's $00 terminator:
;
;   magic0, magic1, total_len, record_count,
;   literal_offset, literal_len, attr0..attrN-1, ...
;
; literal_offset is relative to INPUTBUFFER, i.e. the first tokenized-text byte
; after the four-byte line header. total_len includes the four-byte sidecar
; header. If the scratch buffer overflows, the line is stored unstyled.
; ----------------------------------------------------------------------------
style_side_init:
        lda     #STYLE_SIDE_MAGIC0
        sta     STYLE_SIDE_BUF
        lda     #STYLE_SIDE_MAGIC1
        sta     STYLE_SIDE_BUF+1
        lda     #$04
        sta     STYLE_SIDE_BUF+2
        lda     #$00
        sta     STYLE_SIDE_BUF+3
        sta     STRNG1          ; current record offset in STYLE_SIDE_BUF
        sta     STRNG1+1        ; 0=inactive, 1=active, $80=disabled
        rts

style_side_disable:
        lda     #$00
        sta     STYLE_SIDE_BUF+2
        sta     STRNG1
        lda     #$80
        sta     STRNG1+1
        rts

style_side_begin_literal:
        lda     STRNG1+1
        bmi     @ret
        lda     STYLE_SIDE_BUF+2
        beq     @ret
        cmp     #(STYLE_SIDE_BUF_SIZE-1)
        bcs     @disable
        sta     STRNG1
        txa
        pha
        tya
        pha
        tya                     ; first content byte will be output at Y+1
        sec
        sbc     #$04            ; tokenized-text offset of first content byte
        ldy     STYLE_SIDE_BUF+2
        sta     STYLE_SIDE_BUF,y
        iny
        lda     #$00
        sta     STYLE_SIDE_BUF,y
        iny
        sty     STYLE_SIDE_BUF+2
        lda     #$01
        sta     STRNG1+1
        pla
        tay
        pla
        tax
        rts
@disable:
        jsr     style_side_disable
@ret:
        rts

style_side_append_attr:
        lda     STRNG1+1
        cmp     #$01
        bne     @ret
        lda     STYLE_SIDE_BUF+2
        cmp     #STYLE_SIDE_BUF_SIZE
        bcs     @disable
        txa
        pha
        tya
        pha
        ldy     STYLE_SIDE_BUF+2
        txa
        sec
        sbc     #<INPUTBUFFER
        tax
        lda     INPUTBUFFER,x
        pha
        lda     EDIT_ATTR_BUF,x
        tax
        pla
        jsr     mark_raw_tile_attr
        sta     STYLE_SIDE_BUF,y
        inc     STYLE_SIDE_BUF+2
        ldy     STRNG1
        iny
        lda     STYLE_SIDE_BUF,y
        clc
        adc     #$01
        sta     STYLE_SIDE_BUF,y
        pla
        tay
        pla
        tax
        rts
@disable:
        jsr     style_side_disable
@ret:
        rts

style_side_end_literal:
        lda     STRNG1+1
        cmp     #$01
        bne     @ret
        txa
        pha
        tya
        pha
        ldy     STRNG1
        iny
        lda     STYLE_SIDE_BUF,y
        beq     @empty
        inc     STYLE_SIDE_BUF+3
        jmp     @clear
@empty:
        lda     STRNG1
        sta     STYLE_SIDE_BUF+2
@clear:
        lda     #$00
        sta     STRNG1+1
        pla
        tay
        pla
        tax
@ret:
        rts

style_side_extend_eolpntr:
        jsr     style_side_end_literal
        lda     STYLE_SIDE_BUF+2
        beq     @ret
        lda     STYLE_SIDE_BUF+3
        beq     @ret
        lda     EOLPNTR
        clc
        adc     STYLE_SIDE_BUF+2
        bcs     @memerr
        sta     EOLPNTR
@ret:
        rts
@memerr:
        jmp     MEMERR

style_side_copy_to_program:
        lda     STYLE_SIDE_BUF+2
        beq     @ret
        lda     STYLE_SIDE_BUF+3
        beq     @ret
        lda     LOWTR
        clc
        adc     STYLE_BASE_LEN
        sta     DEST
        lda     LOWTR+1
        adc     #$00
        sta     DEST+1
        ldx     STYLE_SIDE_BUF+2
        ldy     #$00
@loop:
        lda     STYLE_SIDE_BUF,y
        sta     (DEST),y
        iny
        dex
        bne     @loop
@ret:
        rts

style_skip_sidecar_at_index_y:
        sty     STRNG2
        lda     (INDEX),y
        cmp     #STYLE_SIDE_MAGIC0
        bne     @no
        iny
        lda     (INDEX),y
        cmp     #STYLE_SIDE_MAGIC1
        bne     @restore
        iny
        lda     (INDEX),y
        clc
        adc     STRNG2
        tay
        clc
        rts
@restore:
        ldy     STRNG2
@no:
        clc
        rts

SKIP_TXTPTR_SIDECAR:
        ldy     #$01
        lda     (TXTPTR),y
        cmp     #STYLE_SIDE_MAGIC0
        bne     @ret
        iny
        lda     (TXTPTR),y
        cmp     #STYLE_SIDE_MAGIC1
        bne     @ret
        iny
        lda     (TXTPTR),y
        clc
        adc     TXTPTR
        sta     TXTPTR
        bcc     @ret
        inc     TXTPTR+1
@ret:
        rts

mark_raw_tile_attr:
        cmp     #$20
        bcc     @raw
        cmp     #$7F
        bcs     @raw
        txa
        rts
@raw:
        txa
        ora     #STRING_RAW_TILE
        rts

list_style_init:
        lda     #$00
        sta     DATAFLG         ; LIST quote-state: 0=outside, $FF=inside literal
        sta     INDEX
        sta     INDEX+1
        lda     BASIC_DEFAULT_ATTR
        sta     TEXT_ATTR
        ldy     #$04
@find_end:
        iny
        lda     (LOWTRX),y
        bne     @find_end
        iny                     ; Y = optional sidecar offset within the line
        tya
        clc
        adc     LOWTRX
        sta     INDEX
        lda     LOWTRX+1
        adc     #$00
        sta     INDEX+1
        ldy     #$00
        lda     (INDEX),y
        cmp     #STYLE_SIDE_MAGIC0
        bne     @clear
        iny
        lda     (INDEX),y
        cmp     #STYLE_SIDE_MAGIC1
        bne     @clear
        ldy     #$03
        lda     (INDEX),y
        bne     @ret
@clear:
        lda     #$00
        sta     INDEX
        sta     INDEX+1
@ret:
        rts

list_outdo_styled:
        pha                     ; save char
        cmp     #$22
        beq     @quote
        tya
        pha                     ; save tokenized line offset
        lda     DATAFLG
        beq     @plain
        lda     INDEX
        ora     INDEX+1
        beq     @plain
        cpy     #$04
        bcc     @plain
        tya
        sec
        sbc     #$04
        sta     EOLPNTR         ; literal offset within tokenized text
        ldy     #$03
        lda     (INDEX),y
        sta     TEMP1           ; record count
        beq     @plain
        iny                     ; Y = first record offset
@record:
        sty     TEMP2           ; record start within the sidecar
        lda     (INDEX),y
        sta     DIMFLG          ; record literal_offset
        lda     EOLPNTR
        cmp     DIMFLG
        bcc     @plain
        sec
        sbc     DIMFLG          ; A = offset within this literal if in range
        iny
        cmp     (INDEX),y       ; offset < literal_len?
        bcc     @match
        lda     (INDEX),y       ; next record = start + 2 + literal_len
        clc
        adc     TEMP2
        clc
        adc     #$02
        tay
        dec     TEMP1
        bne     @record
        beq     @plain
@match:
        clc
        adc     TEMP2
        clc
        adc     #$02
        tay
        lda     (INDEX),y
        jsr     set_effective_text_attr
        pla
        tay
        pla
        pha
        jsr     styled_outc
        lda     BASIC_DEFAULT_ATTR
        sta     TEXT_ATTR
        pla
        rts
@quote:
        pla
        jsr     OUTDO
        pha
        lda     DATAFLG
        eor     #$FF
        sta     DATAFLG
        pla
        rts
@plain:
        pla
        tay
        pla
        jmp     OUTDO
.endif

.include "inline.s"

; ----------------------------------------------------------------------------
; TOKENIZE THE INPUT LINE
; ----------------------------------------------------------------------------
PARSE_INPUT_LINE:
.ifdef STYLED_STRINGS
        jsr     style_side_init
.endif
        ldx     TXTPTR
        ldy     #$04
        sty     DATAFLG
L246C:
        lda     INPUTBUFFERX,x
.ifdef CONFIG_CBM_ALL
        bpl     LC49E
        cmp     #$FF
        beq     L24AC
        inx
        bne     L246C
LC49E:
.endif
        cmp     #$20
        beq     L24AC
        sta     ENDCHR
        cmp     #$22
.ifdef STYLED_STRINGS
        beq     L24D0_QUOTE
.else
        beq     L24D0
.endif
        bit     DATAFLG
        bvs     L24AC
        cmp     #$3F
        bne     L2484
        lda     #TOKEN_PRINT
        bne     L24AC
  L2484:
.ifdef CLEMENTINA
        jsr     TOKENIZE_MON
        bcs     L24AC
.endif
        cmp     #$30
        bcc     L248C
        cmp     #$3C
        bcc     L24AC
; ----------------------------------------------------------------------------
; SEARCH TOKEN NAME TABLE FOR MATCH STARTING
; WITH CURRENT CHAR FROM INPUT LINE
; ----------------------------------------------------------------------------
L248C:
        sty     STRNG2
        ldy     #$00
        sty     EOLPNTR
        dey
        stx     TXTPTR
        dex
L2496:
        iny
L2497:
        inx
L2498:
.ifdef KBD
        jsr     GET_UPPER
.else
        lda     INPUTBUFFERX,x
  .ifndef CONFIG_2
        cmp     #$20
        beq     L2497
  .endif
.endif
        sec
        sbc     TOKEN_NAME_TABLE,y
        beq     L2496
        cmp     #$80
        bne     L24D7
        ora     EOLPNTR
; ----------------------------------------------------------------------------
; STORE CHARACTER OR TOKEN IN OUTPUT LINE
; ----------------------------------------------------------------------------
L24AA:
        ldy     STRNG2
L24AC:
        inx
        iny
        sta     INPUTBUFFER-5,y
        lda     INPUTBUFFER-5,y
        beq     L24EA
        sec
        sbc     #$3A
        beq     L24BF
        cmp     #$49
        bne     L24C1
L24BF:
        sta     DATAFLG
L24C1:
        sec
        sbc     #TOKEN_REM-':'
        bne     L246C
        sta     ENDCHR
; ----------------------------------------------------------------------------
; HANDLE LITERAL (BETWEEN QUOTES) OR REMARK,
; BY COPYING CHARS UP TO ENDCHR.
; ----------------------------------------------------------------------------
L24C8:
        lda     INPUTBUFFERX,x
        beq     L24AC
        cmp     ENDCHR
.ifdef STYLED_STRINGS
        beq     L24C8_END
.else
        beq     L24AC
.endif
L24D0:
        iny
        sta     INPUTBUFFER-5,y
.ifdef STYLED_STRINGS
        jsr     style_side_append_attr
.endif
        inx
        bne     L24C8
.ifdef STYLED_STRINGS
L24D0_QUOTE:
        iny
        sta     INPUTBUFFER-5,y
        inx
        jsr     style_side_begin_literal
        jmp     L24C8
L24C8_END:
        pha
        jsr     style_side_end_literal
        pla
        jmp     L24AC
.endif
; ----------------------------------------------------------------------------
; ADVANCE POINTER TO NEXT TOKEN NAME
; ----------------------------------------------------------------------------
L24D7:
        ldx     TXTPTR
        inc     EOLPNTR
L24DB:
        iny
        lda     MATHTBL+28+1,y
        bpl     L24DB
        lda     TOKEN_NAME_TABLE,y
        bne     L2498
        lda     INPUTBUFFERX,x
        bpl     L24AA
; ---END OF LINE------------------
L24EA:
        sta     INPUTBUFFER-3,y
.ifdef CONFIG_NO_INPUTBUFFER_ZP
        dec     TXTPTR+1
.endif
        lda     #<(INPUTBUFFER-1)
        sta     TXTPTR
        rts

.ifdef CLEMENTINA
TOKENIZE_MON:
        cmp     #'M'
        beq     @check
        cmp     #'m'
        bne     @no
@check:
        lda     INPUTBUFFERX+1,x
        and     #$DF
        cmp     #'O'
        bne     @restore
        lda     INPUTBUFFERX+2,x
        and     #$DF
        cmp     #'N'
        bne     @restore
        lda     INPUTBUFFERX+3,x
        beq     @emit
        cmp     #$20
        beq     @emit
        cmp     #$3A
        bne     @restore
@emit:
        inx
        inx
        lda     #TOKEN_MON
        sec
        rts
@restore:
        lda     INPUTBUFFERX,x
@no:
        clc
        rts
.endif

; ----------------------------------------------------------------------------
; SEARCH FOR LINE
;
; (LINNUM) = LINE # TO FIND
; IF NOT FOUND:  CARRY = 0
;	LOWTR POINTS AT NEXT LINE
; IF FOUND:      CARRY = 1
;	LOWTR POINTS AT LINE
; ----------------------------------------------------------------------------
FNDLIN:
.ifdef KBD
        jsr     CHRGET
        jmp     LE444
LE440:
        php
        jsr     LINGET
LE444:
        jsr     LF457
        ldx     #$FF
        plp
        beq     LE464
        jsr     CHRGOT
        beq     L2520
        cmp     #$A5
        bne     L2520
        jsr     CHRGET
        beq     LE464
        bcs     LE461
        jsr     LINGET
        beq     L2520
LE461:
        jmp     SYNERR
LE464:
        stx     LINNUM
        stx     LINNUM+1
.else
        lda     TXTTAB
        ldx     TXTTAB+1
FL1:
        ldy     #$01
        sta     LOWTR
        stx     LOWTR+1
        lda     (LOWTR),y
        beq     L251F
        iny
        iny
        lda     LINNUM+1
        cmp     (LOWTR),y
        bcc     L2520
        beq     L250D
        dey
        bne     L2516
L250D:
        lda     LINNUM
        dey
        cmp     (LOWTR),y
        bcc     L2520
        beq     L2520
L2516:
        dey
        lda     (LOWTR),y
        tax
        dey
        lda     (LOWTR),y
        bcs     FL1
L251F:
        clc
.endif
L2520:
        rts

; ----------------------------------------------------------------------------
; "NEW" STATEMENT
; ----------------------------------------------------------------------------
NEW:
        bne     L2520
SCRTCH:
        lda     #$00
        tay
        sta     (TXTTAB),y
        iny
        sta     (TXTTAB),y
        lda     TXTTAB
.ifdef CONFIG_2
		clc
.endif
        adc     #$02
        sta     VARTAB
        lda     TXTTAB+1
        adc     #$00
        sta     VARTAB+1
; ----------------------------------------------------------------------------
SETPTRS:
        jsr     STXTPT
.ifdef CONFIG_11A
        lda     #$00

; ----------------------------------------------------------------------------
; "CLEAR" STATEMENT
; ----------------------------------------------------------------------------
CLEAR:
        bne     L256A
.endif
CLEARC:
.ifdef KBD
        lda     #<CONST_MEMSIZ
        ldy     #>CONST_MEMSIZ
.else
        lda     MEMSIZ
        ldy     MEMSIZ+1
.endif
        sta     FRETOP
        sty     FRETOP+1
.ifdef CONFIG_CBM_ALL
        jsr     CLALL
.endif
        lda     VARTAB
        ldy     VARTAB+1
        sta     ARYTAB
        sty     ARYTAB+1
        sta     STREND
        sty     STREND+1
        jsr     RESTORE
; ----------------------------------------------------------------------------
STKINI:
        ldx     #TEMPST
        stx     TEMPPT
        pla
.ifdef CONFIG_2
		tay
.else
        sta     STACK+STACK_TOP+1
.endif
        pla
.ifndef CONFIG_2
        sta     STACK+STACK_TOP+2
.endif
        ldx     #STACK_TOP
        txs
.ifdef CONFIG_2
        pha
        tya
        pha
.endif
        lda     #$00
        sta     OLDTEXT+1
        sta     SUBFLG
L256A:
        rts

; ----------------------------------------------------------------------------
; SET TXTPTR TO BEGINNING OF PROGRAM
; ----------------------------------------------------------------------------
STXTPT:
        clc
        lda     TXTTAB
        adc     #$FF
        sta     TXTPTR
        lda     TXTTAB+1
        adc     #$FF
        sta     TXTPTR+1
        rts

; ----------------------------------------------------------------------------
.ifdef KBD
LE4C0:
        ldy     #<LE444
        ldx     #>LE444
LE4C4:
        jsr     LFFD6
        jsr     LFFED
        lda     $0504
        clc
        adc     #$08
        sta     $0504
        rts

CMPJMPADRS:
        lda     1,x
        cmp     JMPADRS+2
        bne     LE4DE
        lda     0,x
        cmp     JMPADRS+1
LE4DE:
        rts
.endif

; ----------------------------------------------------------------------------
; "LIST" STATEMENT
; ----------------------------------------------------------------------------
LIST:
.ifdef KBD
        jsr     LE440
        bne     LE4DE
        pla
        pla
L25A6:
        jsr     CRDO
.else
    .ifdef AIM65
        pha
        lda     #$00
LB4BF:
        sta     INPUTFLG
        pla
    .endif
  .ifdef MICROTAN
        php
        jmp     LE21C ; patch
LC57E:
   .elseif .def(AIM65) || .def(SYM1)
        php
        jsr     LINGET
LC57E:
  .else
        bcc     L2581
        beq     L2581
        cmp     #TOKEN_MINUS
        bne     L256A
L2581:
        jsr     LINGET
  .endif
        jsr     FNDLIN
  .if .def(MICROTAN) || .def(AIM65) || .def(SYM1)
        plp
        beq     L2598
  .endif
        jsr     CHRGOT
  .if .def(MICROTAN) || .def(AIM65) || .def(SYM1)
        beq     L25A6
  .else
        beq     L2598
  .endif
        cmp     #TOKEN_MINUS
        bne     L2520
        jsr     CHRGET
  .if .def(MICROTAN) || .def(AIM65) || .def(SYM1)
        beq     L2598
        jsr     LINGET
        beq     L25A6
        rts
  .else
        jsr     LINGET
        bne     L2520
  .endif
L2598:
  .if !(.def(MICROTAN) || .def(AIM65) || .def(SYM1))
        pla
        pla
        lda     LINNUM
        ora     LINNUM+1
        bne     L25A6
  .endif
        lda     #$FF
        sta     LINNUM
        sta     LINNUM+1
L25A6:
  .if .def(MICROTAN) || .def(AIM65) || .def(SYM1)
        pla
        pla
  .endif
L25A6X:
.endif
        ldy     #$01
.ifdef CONFIG_DATAFLG
        sty     DATAFLG
.endif
        lda     (LOWTRX),y
        beq     L25E5
.ifdef MICROTAN
        jmp     LE21F
LC5A9:
.else
        jsr     ISCNTC
.endif
.ifndef KBD
        jsr     CRDO
.endif
        iny
        lda     (LOWTRX),y
        tax
        iny
        lda     (LOWTRX),y
        cmp     LINNUM+1
        bne     L25C1
        cpx     LINNUM
        beq     L25C3
L25C1:
        bcs     L25E5
; ---LIST ONE LINE----------------
L25C3:
        sty     FORPNT
.ifdef STYLED_STRINGS
        pha                     ; LINPRT can clobber LOWTRX via string output
        txa
        pha
        lda     LOWTRX
        sta     STYLE_SIDE_BUF
        lda     LOWTRX+1
        sta     STYLE_SIDE_BUF+1
        pla
        tax
        pla
.endif
        jsr     LINPRT
.ifdef STYLED_STRINGS
        lda     STYLE_SIDE_BUF
        sta     LOWTRX
        lda     STYLE_SIDE_BUF+1
        sta     LOWTRX+1
        jsr     list_style_init
.endif
        lda     #$20
L25CA:
        ldy     FORPNT
        and     #$7F
L25CE:
.ifdef STYLED_STRINGS
        jsr     list_outdo_styled
.else
        jsr     OUTDO
.endif
.ifdef CONFIG_DATAFLG
        cmp     #$22
        bne     LA519
        lda     DATAFLG
        eor     #$FF
        sta     DATAFLG
LA519:
.endif
        iny
.ifdef CONFIG_11
        beq     L25E5
.endif
        lda     (LOWTRX),y
        bne     L25E8
        tay
        lda     (LOWTRX),y
        tax
        iny
        lda     (LOWTRX),y
        stx     LOWTRX
        sta     LOWTRX+1
.if .def(MICROTAN) || .def(AIM65) || .def(SYM1)
        bne     L25A6X
.else
        bne     L25A6
.endif
L25E5:
.ifdef AIM65
        lda     INPUTFLG
        beq     L25E5a
        jsr     CRDO
        jsr     CRDO
        lda     #$1a
        jsr     OUTDO
        jsr     $e50a
L25E5a:
.endif
        jmp     RESTART
  L25E8:
        bpl     L25CE
.ifdef STYLED_STRINGS
        bit     DATAFLG
        bmi     L25CE           ; high tile inside quotes, not a BASIC token
.endif
.ifdef CLEMENTINA
        cmp     #TOKEN_MON
        bne     @not_mon_token
        sty     FORPNT
        lda     #'M'
        jsr     OUTDO
        lda     #'O'
        jsr     OUTDO
        lda     #'N'
        jmp     L25CA
@not_mon_token:
.endif
.ifdef CONFIG_DATAFLG
        cmp     #$FF
        beq     L25CE
        bit     DATAFLG
        bmi     L25CE
.endif
        sec
        sbc     #$7F
        tax
        sty     FORPNT
        ldy     #$FF
L25F2:
        dex
        beq     L25FD
L25F5:
        iny
        lda     TOKEN_NAME_TABLE,y
        bpl     L25F5
        bmi     L25F2
L25FD:
        iny
        lda     TOKEN_NAME_TABLE,y
        bmi     L25CA
        jsr     OUTDO
        bne     L25FD	; always

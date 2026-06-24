.segment "CODE"
; ----------------------------------------------------------------------------
; "STR$" FUNCTION
; ----------------------------------------------------------------------------
STR:
        jsr     CHKNUM
        ldy     #$00
        jsr     FOUT1
        pla
        pla
LD353:
        lda     #<(STACK2-1)
        ldy     #>(STACK2-1)
.if STACK2 > $0100
        bne     STRLIT
.else
        beq     STRLIT
.endif

; ----------------------------------------------------------------------------
; GET SPACE AND MAKE DESCRIPTOR FOR STRING WHOSE
; ADDRESS IS IN FAC+3,4 AND WHOSE LENGTH IS IN A-REG
; ----------------------------------------------------------------------------
STRINI:
        ldx     FAC_LAST-1
        ldy     FAC_LAST
        stx     DSCPTR
        sty     DSCPTR+1

; ----------------------------------------------------------------------------
; GET SPACE AND MAKE DESCRIPTOR FOR STRING WHOSE
; ADDRESS IS IN Y,X AND WHOSE LENGTH IS IN A-REG
; ----------------------------------------------------------------------------
STRSPA:
        jsr     GETSPA
        stx     FAC+1
        sty     FAC+2
        sta     FAC
.ifdef STYLED_STRINGS
        jsr     fill_attr_default
.endif
        rts

.ifdef STYLED_STRINGS
; ----------------------------------------------------------------------------
; fill_attr_default - initialize the attribute half of a freshly allocated
; string to DEFAULT_ATTR. The block is 2N: chars at the base, attrs at base+N.
; In:  FAC = N (logical length), (FAC+1,FAC+2) = base address.
; Out: attr half [base+N, base+2N) filled with DEFAULT_ATTR.
; Clobbers A, Y, INDEX. INDEX is re-established by every caller's character copy
; before use; FRESPC (which that copy relies on) is left untouched. Callers read
; the result from FAC/FAC+1/FAC+2, not from registers. See docs/styled-strings.md.
; ----------------------------------------------------------------------------
fill_attr_default:
        pha                     ; STRSPA must return A = N (the literal-copy path
                                ; in STRLT2 uses it as MOVSTR's byte count)
        lda     FAC+1
        clc
        adc     FAC             ; base + N -> start of the attribute half
        sta     INDEX
        lda     FAC+2
        adc     #$00
        sta     INDEX+1
        ldy     FAC             ; Y = N
        beq     @done
        lda     #DEFAULT_ATTR
@loop:
        dey                     ; dey sets Z; the stores below don't touch flags
        sta     (INDEX),y
        bne     @loop           ; keep A = DEFAULT_ATTR for every byte
@done:
        pla                     ; restore A = N
        rts
.endif

; ----------------------------------------------------------------------------
; BUILD A DESCRIPTOR FOR STRING STARTING AT Y,A
; AND TERMINATED BY $00 OR QUOTATION MARK
; RETURN WITH DESCRIPTOR IN A TEMPORARY
; AND ADDRESS OF DESCRIPTOR IN FAC+3,4
; ----------------------------------------------------------------------------
STRLIT:
        ldx     #$22
        stx     CHARAC
        stx     ENDCHR

; ----------------------------------------------------------------------------
; BUILD A DESCRIPTOR FOR STRING STARTING AT Y,A
; AND TERMINATED BY $00, (CHARAC), OR (ENDCHR)
;
; RETURN WITH DESCRIPTOR IN A TEMPORARY
; AND ADDRESS OF DESCRIPTOR IN FAC+3,4
; ----------------------------------------------------------------------------
STRLT2:
        sta     STRNG1
        sty     STRNG1+1
        sta     FAC+1
        sty     FAC+2
        ldy     #$FF
L3298:
        iny
        lda     (STRNG1),y
        beq     L32A9
        cmp     CHARAC
        beq     L32A5
        cmp     ENDCHR
        bne     L3298
L32A5:
        cmp     #$22
        beq     L32AA
L32A9:
        clc
L32AA:
        sty     FAC
        tya
        adc     STRNG1
        sta     STRNG2
        ldx     STRNG1+1
        bcc     L32B6
        inx
L32B6:
        stx     STRNG2+1
        lda     STRNG1+1
.ifdef CONFIG_NO_INPUTBUFFER_ZP
        beq     LD399
        cmp     #>INPUTBUFFER
.elseif .def(AIM65)
        beq     LD399
        cmp     #$01
.endif
        bne     PUTNEW
LD399:
        tya
        jsr     STRINI
        ldx     STRNG1
        ldy     STRNG1+1
        jsr     MOVSTR
.ifdef STYLED_STRINGS
        ; Phase 4b: route captured attributes. This string was copied from the
        ; input buffer, whose per-cell attributes the editor harvested into
        ; EDIT_ATTR_BUF (EDIT_ATTR_BUF[k] = attr of INPUTBUFFER[k]). MOVSTR left
        ; FRESPC at base+N (the attribute half) and FAC = N (length, set by
        ; STRLT2/STRSPA, untouched by MOVSTR). Copy N attr bytes from
        ; EDIT_ATTR_BUF + (STRNG1 - INPUTBUFFER) over the DEFAULT_ATTR fill, for
        ; input-buffer strings only. Minted strings (CHR$/STR$) never reach here;
        ; program-text literals take the PUTNEW path. See docs/styled-strings.md.
        lda     STRNG1
        sec
        sbc     #<INPUTBUFFER       ; offset of the literal within the input buffer
        clc
        adc     #<EDIT_ATTR_BUF
        sta     INDEX
        lda     #>EDIT_ATTR_BUF
        adc     #$00                ; carry out of the low-byte add
        sta     INDEX+1
        ldy     FAC                 ; Y = N
        beq     @noattr
@acopy:
        dey
        lda     (INDEX),y           ; EDIT_ATTR_BUF[offset + y]
        sta     (FRESPC),y          ; attribute half byte y of the new string
        tya
        bne     @acopy
@noattr:
.endif

; ----------------------------------------------------------------------------
; STORE DESCRIPTOR IN TEMPORARY DESCRIPTOR STACK
;
; THE DESCRIPTOR IS NOW IN FAC, FAC+1, FAC+2
; PUT ADDRESS OF TEMP DESCRIPTOR IN FAC+3,4
; ----------------------------------------------------------------------------
PUTNEW:
        ldx     TEMPPT
        cpx     #TEMPST+9
        bne     PUTEMP
        ldx     #ERR_FRMCPX
JERR:
        jmp     ERROR
PUTEMP:
        lda     FAC
        sta     0,x
        lda     FAC+1
        sta     1,x
        lda     FAC+2
        sta     2,x
        ldy     #$00
        stx     FAC_LAST-1
        sty     FAC_LAST
.ifdef CONFIG_2
        sty     FACEXTENSION
.endif
        dey
        sty     VALTYP
        stx     LASTPT
        inx
        inx
        inx
        stx     TEMPPT
        rts

; ----------------------------------------------------------------------------
; MAKE SPACE FOR STRING AT BOTTOM OF STRING SPACE
; (A)=# BYTES SPACE TO MAKE
;
; RETURN WITH (A) SAME,
;	AND Y,X = ADDRESS OF SPACE ALLOCATED
; ----------------------------------------------------------------------------
GETSPA:
        lsr     DATAFLG
L32F1:
        pha
        eor     #$FF
        sec
        adc     FRETOP
        ldy     FRETOP+1
        bcs     L32FC
        dey
L32FC:
.ifdef STYLED_STRINGS
        ; Reserve a second N bytes for this string's attribute half, so the block
        ; is 2N (N chars followed by N attrs). N is still on the stack from the
        ; pha above; subtract it again, propagating the borrow into Y. The stored
        ; length stays one logical byte (no 127 cap). See docs/styled-strings.md.
        sec
        tsx
        sbc     $0101,x
        bcs     :+
        dey
:
.endif
        cpy     STREND+1
        bcc     L3311
        bne     L3306
        cmp     STREND
        bcc     L3311
L3306:
        sta     FRETOP
        sty     FRETOP+1
        sta     FRESPC
        sty     FRESPC+1
        tax
        pla
        rts
L3311:
        ldx     #ERR_MEMFULL
        lda     DATAFLG
        bmi     JERR
        jsr     GARBAG
        lda     #$80
        sta     DATAFLG
        pla
        bne     L32F1

; ----------------------------------------------------------------------------
; SHOVE ALL REFERENCED STRINGS AS HIGH AS POSSIBLE
; IN MEMORY (AGAINST HIMEM), FREEING UP SPACE
; BELOW STRING AREA DOWN TO STREND.
; ----------------------------------------------------------------------------
GARBAG:

.ifdef CONST_MEMSIZ
        ldx     #<CONST_MEMSIZ
        lda     #>CONST_MEMSIZ
.else
        ldx     MEMSIZ
        lda     MEMSIZ+1
.endif
FINDHIGHESTSTRING:
        stx     FRETOP
        sta     FRETOP+1
        ldy     #$00
        sty     FNCNAM+1
.ifdef CONFIG_2
        sty     FNCNAM	; GC bugfix!
.endif
        lda     STREND
        ldx     STREND+1
        sta     LOWTR
        stx     LOWTR+1
        lda     #TEMPST
        ldx     #$00
        sta     INDEX
        stx     INDEX+1
L333D:
        cmp     TEMPPT
        beq     L3346
        jsr     CHECK_VARIABLE
        beq     L333D
L3346:
        lda     #BYTES_PER_VARIABLE
        sta     DSCLEN
        lda     VARTAB
        ldx     VARTAB+1
        sta     INDEX
        stx     INDEX+1
L3352:
        cpx     ARYTAB+1
        bne     L335A
        cmp     ARYTAB
        beq     L335F
L335A:
        jsr     CHECK_SIMPLE_VARIABLE
        beq     L3352
L335F:
        sta     HIGHDS
        stx     HIGHDS+1
        lda     #$03	; OSI GC bugfix -> $04 ???
        sta     DSCLEN
L3367:
        lda     HIGHDS
        ldx     HIGHDS+1
L336B:
        cpx     STREND+1
        bne     L3376
        cmp     STREND
        bne     L3376
        jmp     MOVE_HIGHEST_STRING_TO_TOP
L3376:
        sta     INDEX
        stx     INDEX+1
.ifdef CONFIG_SMALL
        ldy     #$01
.else
        ldy     #$00
        lda     (INDEX),y
        tax
        iny
.endif
        lda     (INDEX),y
        php
        iny
        lda     (INDEX),y
        adc     HIGHDS
        sta     HIGHDS
        iny
        lda     (INDEX),y
        adc     HIGHDS+1
        sta     HIGHDS+1
        plp
        bpl     L3367
.ifndef CONFIG_SMALL
        txa
        bmi     L3367
.endif
        iny
        lda     (INDEX),y
.ifdef CONFIG_CBM1_PATCHES
        jsr     LE7F3 ; XXX patch, call into screen editor
.else
  .ifdef CONFIG_11
        ldy     #$00	; GC bugfix
  .endif
        asl     a
        adc     #$05
.endif
        adc     INDEX
        sta     INDEX
        bcc     L33A7
        inc     INDEX+1
L33A7:
        ldx     INDEX+1
L33A9:
        cpx     HIGHDS+1
        bne     L33B1
        cmp     HIGHDS
        beq     L336B
L33B1:
        jsr     CHECK_VARIABLE
        beq     L33A9

; ----------------------------------------------------------------------------
; PROCESS A SIMPLE VARIABLE
; ----------------------------------------------------------------------------
CHECK_SIMPLE_VARIABLE:
.ifndef CONFIG_SMALL
        lda     (INDEX),y
        bmi     CHECK_BUMP
.endif
        iny
        lda     (INDEX),y
        bpl     CHECK_BUMP
        iny

; ----------------------------------------------------------------------------
; IF STRING IS NOT EMPTY, CHECK IF IT IS HIGHEST
; ----------------------------------------------------------------------------
CHECK_VARIABLE:
        lda     (INDEX),y
        beq     CHECK_BUMP
        iny
        lda     (INDEX),y
        tax
        iny
        lda     (INDEX),y
        cmp     FRETOP+1
        bcc     L33D5
        bne     CHECK_BUMP
        cpx     FRETOP
        bcs     CHECK_BUMP
L33D5:
        cmp     LOWTR+1
        bcc     CHECK_BUMP
        bne     L33DF
        cpx     LOWTR
        bcc     CHECK_BUMP
L33DF:
        stx     LOWTR
        sta     LOWTR+1
        lda     INDEX
        ldx     INDEX+1
        sta     FNCNAM
        stx     FNCNAM+1
        lda     DSCLEN
        sta     Z52

; ----------------------------------------------------------------------------
; ADD (DSCLEN) TO PNTR IN INDEX
; RETURN WITH Y=0, PNTR ALSO IN X,A
; ----------------------------------------------------------------------------
CHECK_BUMP:
        lda     DSCLEN
        clc
        adc     INDEX
        sta     INDEX
        bcc     L33FA
        inc     INDEX+1
L33FA:
        ldx     INDEX+1
        ldy     #$00
        rts

; ----------------------------------------------------------------------------
; FOUND HIGHEST NON-EMPTY STRING, SO MOVE IT
; TO TOP AND GO BACK FOR ANOTHER
; ----------------------------------------------------------------------------
MOVE_HIGHEST_STRING_TO_TOP:
.ifdef CONFIG_2
        lda     FNCNAM+1	; GC bugfix
        ora     FNCNAM
.else
        ldx     FNCNAM+1
.endif
        beq     L33FA
        lda     Z52
.ifndef CONFIG_10A
        sbc     #$03
.else
        and     #$04
.endif
        lsr     a
        tay
        sta     Z52
        lda     (FNCNAM),y
        adc     LOWTR
        sta     HIGHTR
        lda     LOWTR+1
        adc     #$00
        sta     HIGHTR+1
.ifdef STYLED_STRINGS
        ; The string occupies 2N bytes (chars + attrs): add the length a second
        ; time so the whole block is relocated, not just the char half. Y still
        ; points at the descriptor's length byte. See docs/styled-strings.md.
        lda     (FNCNAM),y
        clc
        adc     HIGHTR
        sta     HIGHTR
        bcc     :+
        inc     HIGHTR+1
:
.endif
        lda     FRETOP
        ldx     FRETOP+1
        sta     HIGHDS
        stx     HIGHDS+1
        jsr     BLTU2
        ldy     Z52
        iny
        lda     HIGHDS
        sta     (FNCNAM),y
        tax
        inc     HIGHDS+1
        lda     HIGHDS+1
        iny
        sta     (FNCNAM),y
        jmp     FINDHIGHESTSTRING

; ----------------------------------------------------------------------------
; CONCATENATE TWO STRINGS
; ----------------------------------------------------------------------------
CAT:
        lda     FAC_LAST
        pha
        lda     FAC_LAST-1
        pha
        jsr     FRM_ELEMENT
        jsr     CHKSTR
        pla
        sta     STRNG1
        pla
        sta     STRNG1+1
        ldy     #$00
        lda     (STRNG1),y
        clc
        adc     (FAC_LAST-1),y
        bcc     L3454
        ldx     #ERR_STRLONG
        jmp     ERROR
L3454:
        jsr     STRINI
.ifdef STYLED_STRINGS
        jsr     cat_classify    ; record left/right heap flags while both are live
.endif
        jsr     MOVINS
        lda     DSCPTR
        ldy     DSCPTR+1
        jsr     FRETMP
        jsr     MOVSTR1
.ifdef STYLED_STRINGS
        jsr     cat_attrs       ; append left then right attr runs to the result
.endif
        lda     STRNG1
        ldy     STRNG1+1
        jsr     FRETMP
        jsr     PUTNEW
        jmp     FRMEVL2

; ----------------------------------------------------------------------------
; GET STRING DESCRIPTOR POINTED AT BY (STRNG1)
; AND MOVE DESCRIBED STRING TO (FRESPC)
; ----------------------------------------------------------------------------
MOVINS:
        ldy     #$00
        lda     (STRNG1),y
        pha
        iny
        lda     (STRNG1),y
        tax
        iny
        lda     (STRNG1),y
        tay
        pla

; ----------------------------------------------------------------------------
; MOVE STRING AT (Y,X) WITH LENGTH (A)
; TO DESTINATION WHOSE ADDRESS IS IN FRESPC,FRESPC+1
; ----------------------------------------------------------------------------
MOVSTR:
        stx     INDEX
        sty     INDEX+1
MOVSTR1:
        tay
        beq     L3490
        pha
L3487:
        dey
        lda     (INDEX),y
        sta     (FRESPC),y
        tya
        bne     L3487
        pla
L3490:
        clc
        adc     FRESPC
        sta     FRESPC
        bcc     L3499
        inc     FRESPC+1
L3499:
        rts

.ifdef STYLED_STRINGS
; ----------------------------------------------------------------------------
; append_attr_run - place one source string's attribute run into the result
; being built at FRESPC (Phase 1c: slice/concat attribute propagation).
; In:  A     = count (this source's logical length)
;      INDEX = source attribute pointer (source data ptr + source length); only
;              read when the source is a heap string
;      X     = nonzero if the source is a heap string (has an attribute half, so
;              copy its attrs); zero if it is a program-text literal (no attr
;              half - leave the DEFAULT_ATTR fill in place and just step over it)
; Out: FRESPC advanced by count. Clobbers A, Y (and, on the heap path, INDEX).
; See docs/styled-strings.md §3.4.
; ----------------------------------------------------------------------------
append_attr_run:
        cpx     #$00
        bne     MOVSTR1         ; heap: copy count attrs from INDEX, advance FRESPC
        clc                     ; literal: keep the default fill, advance FRESPC
        adc     FRESPC
        sta     FRESPC
        bcc     :+
        inc     FRESPC+1
:       rts

; ----------------------------------------------------------------------------
; classify_heap - decide whether the string whose 3-byte descriptor is at
; (INDEX) is a live heap string (data ptr >= FRETOP, so it carries an attribute
; half) or a program-text literal (no attr half). Callers must invoke this while
; the string is still live - before any FRETMP frees it and raises FRETOP past
; it. In: INDEX -> descriptor. Out: A = 1 heap / 0 literal. Clobbers A, Y.
; See docs/styled-strings.md §3.4/§5.
; ----------------------------------------------------------------------------
classify_heap:
        ldy     #$02
        lda     (INDEX),y       ; data ptr hi
        cmp     FRETOP+1
        bcc     @lit
        bne     @heap
        dey
        lda     (INDEX),y       ; data ptr lo
        cmp     FRETOP
        bcc     @lit
@heap:  lda     #$01
        rts
@lit:   lda     #$00
        rts

; ----------------------------------------------------------------------------
; slice_attrs - copy a substring's attribute run (LEFT$/RIGHT$/MID$, Phase 1c).
; Entered after the char copy with INDEX = parent data ptr + start and FRESPC =
; result base + count. The parent attr half is at parent data ptr + parentLen,
; so the slice's attr source = INDEX + parentLen; parentLen is at (DSCPTR),0,
; count is in FAC, and DEST (set by classify_heap before the parent was freed)
; says whether the parent had attrs. See docs/styled-strings.md §3.4.
; ----------------------------------------------------------------------------
slice_attrs:
        ldy     #$00
        lda     (DSCPTR),y      ; parentLen
        clc
        adc     INDEX
        sta     INDEX
        bcc     :+
        inc     INDEX+1
:       ldx     DEST            ; 1 = parent heap (copy), 0 = literal (default fill)
        lda     FAC             ; count = slice length
        jmp     append_attr_run

; ----------------------------------------------------------------------------
; append_desc_attrs - append to the result at FRESPC the attribute run of the
; source string whose 3-byte descriptor is at (INDEX). In: INDEX -> descriptor;
; X = heap flag (1 copy attrs / 0 literal -> keep default fill). The source attr
; run lives at the source's data ptr + its length. Out: FRESPC advanced by the
; source length. Clobbers A, Y, INDEX (X preserved into append_attr_run).
; ----------------------------------------------------------------------------
append_desc_attrs:
        ldy     #$00
        lda     (INDEX),y       ; source length
        pha                     ; save count
        ldy     #$01
        lda     (INDEX),y       ; source data ptr lo
        pha
        ldy     #$02
        lda     (INDEX),y       ; source data ptr hi
        sta     INDEX+1
        pla                     ; data ptr lo
        sta     INDEX           ; INDEX = source data ptr
        pla                     ; count
        pha                     ; keep a copy
        clc
        adc     INDEX           ; INDEX = data ptr + length = source attr run
        sta     INDEX
        bcc     :+
        inc     INDEX+1
:       pla                     ; A = count
        jmp     append_attr_run

; ----------------------------------------------------------------------------
; cat_classify / cat_attrs - CAT (string concatenation) attribute propagation.
; cat_classify records, while both operands are still live (after STRINI, before
; the operands are freed), whether each carries an attr half: DEST = left flag
; (descriptor at STRNG1), DEST+1 = right flag (descriptor at DSCPTR). cat_attrs
; then appends left then right attr runs to the result at FRESPC (after both
; char halves are in place, FRESPC = result base + total length). The operand
; descriptors and their data survive FRETMP (which only raises FRETOP), and the
; result is built below them, so the sources are still readable here.
; See docs/styled-strings.md §3.4.
; ----------------------------------------------------------------------------
cat_classify:
        lda     STRNG1
        sta     INDEX
        lda     STRNG1+1
        sta     INDEX+1
        jsr     classify_heap
        sta     DEST
        lda     DSCPTR
        sta     INDEX
        lda     DSCPTR+1
        sta     INDEX+1
        jsr     classify_heap
        sta     DEST+1
        rts

cat_attrs:
        lda     STRNG1
        sta     INDEX
        lda     STRNG1+1
        sta     INDEX+1
        ldx     DEST            ; left heap flag
        jsr     append_desc_attrs
        lda     DSCPTR
        sta     INDEX
        lda     DSCPTR+1
        sta     INDEX+1
        ldx     DEST+1          ; right heap flag
        jmp     append_desc_attrs
.endif

; ----------------------------------------------------------------------------
; IF (FAC) IS A TEMPORARY STRING, RELEASE DESCRIPTOR
; ----------------------------------------------------------------------------
FRESTR:
        jsr     CHKSTR

; ----------------------------------------------------------------------------
; IF STRING DESCRIPTOR POINTED TO BY FAC+3,4 IS
; A TEMPORARY STRING, RELEASE IT.
; ----------------------------------------------------------------------------
FREFAC:
        lda     FAC_LAST-1
        ldy     FAC_LAST

; ----------------------------------------------------------------------------
; IF STRING DESCRIPTOR WHOSE ADDRESS IS IN Y,A IS
; A TEMPORARY STRING, RELEASE IT.
; ----------------------------------------------------------------------------
FRETMP:
        sta     INDEX
        sty     INDEX+1
        jsr     FRETMS
        php
        ldy     #$00
        lda     (INDEX),y
        pha
        iny
        lda     (INDEX),y
        tax
        iny
        lda     (INDEX),y
        tay
        pla
        plp
        bne     L34CD
        cpy     FRETOP+1
        bne     L34CD
        cpx     FRETOP
        bne     L34CD
.ifdef STYLED_STRINGS
        ; The freed block is 2N (chars + attrs); bump FRETOP by the length twice.
        ; A holds the logical length N on entry and is restored to N on exit
        ; (CAT relies on FRETMP returning the length in A).
        pha
        clc
        adc     FRETOP
        sta     FRETOP
        bcc     :+
        inc     FRETOP+1
:       pla
        pha
        clc
        adc     FRETOP
        sta     FRETOP
        bcc     :+
        inc     FRETOP+1
:       pla
.else
        pha
        clc
        adc     FRETOP
        sta     FRETOP
        bcc     L34CC
        inc     FRETOP+1
L34CC:
        pla
.endif
L34CD:
        stx     INDEX
        sty     INDEX+1
        rts

; ----------------------------------------------------------------------------
; RELEASE TEMPORARY DESCRIPTOR IF Y,A = LASTPT
; ----------------------------------------------------------------------------
FRETMS:
.ifdef KBD
        cpy     #$00
.else
        cpy     LASTPT+1
.endif
        bne     L34E2
        cmp     LASTPT
        bne     L34E2
        sta     TEMPPT
        sbc     #$03
        sta     LASTPT
        ldy     #$00
L34E2:
        rts

; ----------------------------------------------------------------------------
; "CHR$" FUNCTION
; ----------------------------------------------------------------------------
CHRSTR:
        jsr     CONINT
        txa
        pha
        lda     #$01
        jsr     STRSPA
        pla
        ldy     #$00
        sta     (FAC+1),y
        pla
        pla
        jmp     PUTNEW

; ----------------------------------------------------------------------------
; "LEFT$" FUNCTION
; ----------------------------------------------------------------------------
LEFTSTR:
        jsr     SUBSTRING_SETUP
        cmp     (DSCPTR),y
        tya
SUBSTRING1:
        bcc     L3503
        lda     (DSCPTR),y
        tax
        tya
L3503:
        pha
SUBSTRING2:
        txa
SUBSTRING3:
        pha
        jsr     STRSPA
.ifdef STYLED_STRINGS
        ; Classify the parent while still live (before the FRETMP below frees it
        ; and raises FRETOP past it). DEST = 1 heap / 0 literal. See §3.4/§5.
        lda     DSCPTR
        sta     INDEX
        lda     DSCPTR+1
        sta     INDEX+1
        jsr     classify_heap
        sta     DEST
.endif
        lda     DSCPTR
        ldy     DSCPTR+1
        jsr     FRETMP
        pla
        tay
        pla
        clc
        adc     INDEX
        sta     INDEX
        bcc     L351C
        inc     INDEX+1
L351C:
        tya
        jsr     MOVSTR1
.ifdef STYLED_STRINGS
        jsr     slice_attrs     ; copy the slice's attr run (or keep default fill)
.endif
        jmp     PUTNEW

; ----------------------------------------------------------------------------
; "RIGHT$" FUNCTION
; ----------------------------------------------------------------------------
RIGHTSTR:
        jsr     SUBSTRING_SETUP
        clc
        sbc     (DSCPTR),y
        eor     #$FF
        jmp     SUBSTRING1

; ----------------------------------------------------------------------------
; "MID$" FUNCTION
; ----------------------------------------------------------------------------
MIDSTR:
        lda     #$FF
        sta     FAC_LAST
        jsr     CHRGOT
        cmp     #$29
        beq     L353F
        jsr     CHKCOM
        jsr     GETBYT
L353F:
        jsr     SUBSTRING_SETUP
.ifdef CONFIG_2
        beq     GOIQ
.endif
        dex
        txa
        pha
        clc
        ldx     #$00
        sbc     (DSCPTR),y
        bcs     SUBSTRING2
        eor     #$FF
        cmp     FAC_LAST
        bcc     SUBSTRING3
        lda     FAC_LAST
        bcs     SUBSTRING3

; ----------------------------------------------------------------------------
; COMMON SETUP ROUTINE FOR LEFT$, RIGHT$, MID$:
; REQUIRE ")"; POP RETURN ADRS, GET DESCRIPTOR
; ADDRESS, GET 1ST PARAMETER OF COMMAND
; ----------------------------------------------------------------------------
SUBSTRING_SETUP:
        jsr     CHKCLS
        pla
.ifndef CONFIG_11
        sta     JMPADRS+1
        pla
        sta     JMPADRS+2
.else
        tay
        pla
        sta     Z52
.endif
        pla
        pla
        pla
        tax
        pla
        sta     DSCPTR
        pla
        sta     DSCPTR+1
.ifdef CONFIG_11
        lda     Z52
        pha
        tya
        pha
.endif
        ldy     #$00
        txa
.ifndef CONFIG_2
        beq     GOIQ
.endif
.ifndef CONFIG_11
        inc     JMPADRS+1
        jmp     (JMPADRS+1)
.else
        rts
.endif

; ----------------------------------------------------------------------------
; "LEN" FUNCTION
; ----------------------------------------------------------------------------
LEN:
        jsr     GETSTR
SNGFLT1:
        jmp     SNGFLT

; ----------------------------------------------------------------------------
; IF LAST RESULT IS A TEMPORARY STRING, FREE IT
; MAKE VALTYP NUMERIC, RETURN LENGTH IN Y-REG
; ----------------------------------------------------------------------------
GETSTR:
        jsr     FRESTR
        ldx     #$00
        stx     VALTYP
        tay
        rts

; ----------------------------------------------------------------------------
; "ASC" FUNCTION
; ----------------------------------------------------------------------------
ASC:
        jsr     GETSTR
        beq     GOIQ
        ldy     #$00
        lda     (INDEX),y
        tay
.ifndef CONFIG_11A
        jmp     SNGFLT1
.else
        jmp     SNGFLT
.endif
; ----------------------------------------------------------------------------
GOIQ:
        jmp     IQERR

; ----------------------------------------------------------------------------
; SCAN TO NEXT CHARACTER AND CONVERT EXPRESSION
; TO SINGLE BYTE IN X-REG
; ----------------------------------------------------------------------------
GTBYTC:
        jsr     CHRGET

; ----------------------------------------------------------------------------
; EVALUATE EXPRESSION AT TXTPTR, AND
; CONVERT IT TO SINGLE BYTE IN X-REG
; ----------------------------------------------------------------------------
GETBYT:
        jsr     FRMNUM

; ----------------------------------------------------------------------------
; CONVERT (FAC) TO SINGLE BYTE INTEGER IN X-REG
; ----------------------------------------------------------------------------
CONINT:
        jsr     MKINT
        ldx     FAC_LAST-1
        bne     GOIQ
        ldx     FAC_LAST
        jmp     CHRGOT

; ----------------------------------------------------------------------------
; "VAL" FUNCTION
; ----------------------------------------------------------------------------
VAL:
        jsr     GETSTR
        bne     L35AC
        jmp     ZERO_FAC
L35AC:
        ldx     TXTPTR
        ldy     TXTPTR+1
        stx     STRNG2
        sty     STRNG2+1
        ldx     INDEX
        stx     TXTPTR
        clc
        adc     INDEX
        sta     DEST
        ldx     INDEX+1
        stx     TXTPTR+1
        bcc     L35C4
        inx
L35C4:
        stx     DEST+1
        ldy     #$00
        lda     (DEST),y
        pha
        lda     #$00
        sta     (DEST),y
        jsr     CHRGOT
        jsr     FIN
        pla
        ldy     #$00
        sta     (DEST),y

; ----------------------------------------------------------------------------
; COPY STRNG2 INTO TXTPTR
; ----------------------------------------------------------------------------
POINT:
        ldx     STRNG2
        ldy     STRNG2+1
        stx     TXTPTR
        sty     TXTPTR+1
        rts


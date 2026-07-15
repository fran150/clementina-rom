; ============================================================================
; clementina_extra.s - Clementina BASIC console glue (EXTRA segment)
; ----------------------------------------------------------------------------
; Thin thunks from BASIC's console contract into the Clementina kernel jump
; table. In the combined image the kernel lives at $0400 and owns the console.
; Keep these addresses in sync with src/kernel/kernel.inc / docs/memory-map.md.
; ============================================================================

.segment "EXTRA"
.export BASIC_COLD_START, BASIC_WARM_START, MONRDKEY, MONRDKEY_NB, MONCOUT, MONRDLINE

KERN_CHROUT       = $0406
KERN_CHRIN        = $0409
KERN_GETKEY_NB    = $040C
KERN_EDITKEY      = $0424
KERN_CHROUT_GLYPH = $0427
KERN_WOZMON       = $042A

; Console control codes (CHROUT interprets these) and overlay geometry. Keep in
; sync with src/kernel/kernel.inc.
CHR_FF            = $0C    ; form feed: clear screen and home the cursor
CHR_CRSR_DOWN     = $11    ; cursor down one row
CHR_HOME          = $13    ; cursor to top-left
CHR_CRSR_RIGHT    = $1D    ; cursor right one cell
SCR_COLS          = 40
SCR_ROWS          = 25

BASIC_COLD_START:
        jmp COLD_START

; Warm restart: keep the current program/variables and return to the READY
; prompt. Used by the kernel warmstart entry (KERN_WARMSTART) so a user can quit
; the WOZ monitor back to BASIC without losing their program.
BASIC_WARM_START:
        jmp RESTART

; A = character to print. Kernel CHROUT preserves A/X/Y.
MONCOUT:
        jmp KERN_CHROUT

; Blocking read; returns the character in A.
MONRDKEY:
        jmp KERN_CHRIN

; Non-blocking read; C=1 and A=char if available, else C=0.
MONRDKEY_NB:
        jmp KERN_GETKEY_NB

; Line-input reader: returns the next character of the screen-edited logical
; line (printable bytes then a terminating CR). BASIC's GETLN uses this so line
; editing runs in the kernel; GET keeps using the raw single-char MONRDKEY.
MONRDLINE:
        jmp KERN_EDITKEY

; Enter the WOZ monitor. Return to BASIC from WozMon with Q.
BASIC_MON:
        jmp KERN_WOZMON

; ----------------------------------------------------------------------------
; BASIC console statements
;
; MON       enter the WOZ monitor; return to BASIC from WozMon with Q.
; CLS       clear the screen and home the cursor.
; CRSR x,y  move the cursor to column x (0..SCR_COLS-1), row y (0..SCR_ROWS-1).
;           0,0 is the top-left corner; 39,24 the bottom-right.
;
; Both drive the cursor through the kernel console (MONCOUT/CHROUT) so the
; software cursor glyph and the logical-line link table stay consistent: CLS
; emits a form feed (clrscr + home), CRSR homes then steps the cursor with
; the cursor-down / cursor-right control codes. Out-of-range arguments raise
; ILLEGAL QUANTITY, matching COLOR/STYLE.
;
; NOTE: these keyword names are short on purpose. BASIC's tokenizer indexes the
; keyword name table with an 8-bit Y register, so ALL keyword names plus the
; terminator must fit in 256 bytes (see token.s). Long names overflow the table
; and hang the tokenizer on every typed line.
; ----------------------------------------------------------------------------
BASIC_CLS:
        lda     #$00
        sta     POSX                    ; BASIC column tracker: home is column 0
        lda     #CHR_FF
        jmp     MONCOUT                 ; clear + home (tail call; cursor handled)

BASIC_CRSR:
        jsr     GETBYT                  ; X = column
        cpx     #SCR_COLS
        bcs     @iq
        stx     LINNUM                  ; survives the second GETBYT (POKE pattern)
        jsr     COMBYTE                 ; X = row
        cpx     #SCR_ROWS
        bcs     @iq
        lda     #CHR_HOME
        jsr     MONCOUT                 ; cursor to (0,0); preserves X
        txa                             ; A = row count (sets Z)
        beq     @cols
@rows:
        lda     #CHR_CRSR_DOWN
        jsr     MONCOUT                 ; preserves X
        dex
        bne     @rows
@cols:
        ldx     LINNUM
        beq     @done
@colloop:
        lda     #CHR_CRSR_RIGHT
        jsr     MONCOUT                 ; preserves X
        dex
        bne     @colloop
@done:
        lda     LINNUM                  ; column = LINNUM (preserved through MONCOUT)
        sta     POSX                    ; keep BASIC's column (POS/TAB/PRINT) in sync
        rts
@iq:
        jmp     IQERR

; MONCOUT routes A through the kernel console; chrout preserves A/X/Y, so the
; loops above can hold their counter in X across the call.

.ifdef STYLED_STRINGS
; ----------------------------------------------------------------------------
; BASIC style commands
;
; COLOR n       sets default palette color 0-15
; FLIPX/FLIPY n set/clear default flip bits (0=clear, nonzero=set)
; ALT n         set/clear default CHR_ALT/reverse bit (0=clear, nonzero=set)
; STYLE n       policy bitmask, user bits: 1=color, 2=flipX, 4=flipY, 8=ALT.
;               Internally stored as an overlay-attribute override mask:
;               $0F/$10/$20/$80. Bit off means use stored style; bit on means
;               use BASIC_DEFAULT_ATTR for that field.
; ----------------------------------------------------------------------------
BASIC_COLOR:
        jsr     GETBYT
        txa
        cmp     #$10
        bcs     @iq
        sta     TEMP1
        lda     BASIC_DEFAULT_ATTR
        and     #$B0            ; keep flip-X, flip-Y, CHR_ALT; clear color/raw
        ora     TEMP1
        jmp     style_store_default_attr
@iq:
        jmp     IQERR

BASIC_FLIPX:
        jsr     GETBYT
        lda     #$10
        jmp     style_set_default_bit

BASIC_FLIPY:
        jsr     GETBYT
        lda     #$20
        jmp     style_set_default_bit

BASIC_ALT:
        jsr     GETBYT
        lda     #$80
        jmp     style_set_default_bit

style_set_default_bit:
        sta     TEMP1
        txa
        beq     @clear
        lda     BASIC_DEFAULT_ATTR
        ora     TEMP1
        jmp     style_store_default_attr
@clear:
        lda     TEMP1
        eor     #$FF
        and     BASIC_DEFAULT_ATTR
style_store_default_attr:
        and     #DISPLAY_ATTR_MASK
        sta     BASIC_DEFAULT_ATTR      ; COLOR/FLIPX/FLIPY/ALT set the BASIC pen only.
        rts                             ; The live editor pen (TEXT_ATTR) is independent
                                        ; and is never overwritten here.

BASIC_STYLE:
        jsr     GETBYT
        txa
        cmp     #$10
        bcs     @iq
        lda     #$00
        sta     TEMP1
        txa
        and     #$01
        beq     :+
        lda     TEMP1
        ora     #$0F
        sta     TEMP1
:       txa
        and     #$02
        beq     :+
        lda     TEMP1
        ora     #$10
        sta     TEMP1
:       txa
        and     #$04
        beq     :+
        lda     TEMP1
        ora     #$20
        sta     TEMP1
:       txa
        and     #$08
        beq     :+
        lda     TEMP1
        ora     #$80
        sta     TEMP1
:       lda     TEMP1
        sta     BASIC_STYLE_MASK
        rts
@iq:
        jmp     IQERR

; A = stored string attr, including BASIC's internal STRING_RAW_TILE marker.
; Stores the effective attr into TEXT_ATTR according to BASIC_STYLE_MASK.
set_effective_text_attr:
        sta     TEMP1
        lda     BASIC_STYLE_MASK
        eor     #$FF
        and     TEMP1
        sta     TEMP1
        lda     BASIC_DEFAULT_ATTR
        and     BASIC_STYLE_MASK
        ora     TEMP1
        sta     TEXT_ATTR
        rts

; A = tile -> console drawn as a raw glyph, never interpreted as a control code.
; Used by STRPRT_STYLED for the high/graphic tile codes that styled strings carry
; (which would otherwise hit chrout's cursor-move/CR handling). Preserves A/X/Y.
MONCOUT_GLYPH:
        jmp KERN_CHROUT_GLYPH
.endif

.ifdef STYLED_STRINGS
; ----------------------------------------------------------------------------
; STRPRT_STYLED - PRINT a string applying per-character attributes. Entered via
; an absolute jmp from STRPRT (print.s) with A = N (length) and INDEX = character
; data pointer; FREFAC has already run. Heap strings carry an attribute half at
; (data + N); program-text literals/messages do not, and print at BASIC_DEFAULT_ATTR.
; Classify by data address: program text/messages below STREND are literals; heap
; strings sit at or above the heap bottom. We compare heap strings against DEST,
; a snapshot of FRETOP that STRPRT takes *before* FREFAC: FREFAC frees a printed
; temp and raises FRETOP above it, but the temp keeps its bytes (including the
; attr half), so classifying against the post-free FRETOP would misread a styled
; temp (PRINT A$+B$, PRINT LEFT$(A$,3)) as a literal. Lives in the EXTRA segment
; so it never perturbs the CODE segment's tight branches. See
; docs/styled-strings.md §3.7/§5.
; ----------------------------------------------------------------------------
STRPRT_STYLED:
        tax                     ; hold N while we stack the live pen
        lda     TEXT_ATTR
        pha                     ; save the pen *under* N; every exit restores it, so a
        txa                     ; styled string (whose per-char loop rewrites TEXT_ATTR)
        pha                     ; leaves the pen unchanged. Then save N, as before.
        lda     STREND
        ora     STREND+1
        beq     @class_heap
        ldy     INDEX+1
        cpy     STREND+1
        bcc     @lit
        bne     @class_heap
        ldy     INDEX
        cpy     STREND
        bcc     @lit
@class_heap:
        ldy     INDEX+1
        cpy     DEST+1          ; DEST = FRETOP snapshot from STRPRT (pre-FREFAC)
        bcc     @lit
        bne     @heap
        ldy     INDEX
        cpy     DEST
        bcc     @lit
@heap:
        pla                     ; A = N
        pha
        clc
        adc     INDEX           ; FRESPC = data + N (attribute base)
        sta     FRESPC
        lda     INDEX+1
        adc     #$00
        sta     FRESPC+1
        pla                     ; A = N
        tax
        ldy     #$00
        inx
@hloop:
        dex
        beq     @hdone
        lda     (FRESPC),y      ; this character's attribute
        jsr     set_effective_text_attr
        lda     (INDEX),y       ; the character / tile
        jsr     styled_outc
        iny
        jmp     @hloop
@hdone:
        pla                     ; restore the pen saved at entry (the editor pen for
        sta     TEXT_ATTR       ; user output; the BASIC pen for a STROUT message)
        rts
@lit:
        ; Literals/messages carry no attribute half and are plain unstyled text -
        ; including CR/LF formatting that CHROUT must interpret (e.g. message
        ; strings begin with CR+LF, and LF is ignored). So print them through plain
        ; OUTDO, exactly as before Phase 5: only the heap path (which can carry
        ; graphic tile codes) needs the raw-glyph treatment. They print at the live
        ; pen: user PRINT output keeps the editor pen; a system message arrives here
        ; with the BASIC pen already loaded by STROUT (print.s).
        pla                     ; A = N
        tax
        ldy     #$00
        inx
@lloop:
        dex
        beq     @ldone
        lda     (INDEX),y
        jsr     OUTDO
        iny
        cmp     #$0D
        bne     @lloop
        jsr     PRINTNULLS
        jmp     @lloop
@ldone:
        pla                     ; balance the pen saved at entry (literals leave it
        sta     TEXT_ATTR       ; unchanged, so this just restores the same value)
        rts

; ----------------------------------------------------------------------------
; styled_outc - output one byte of a *heap* (styled) string, pen already in
; TEXT_ATTR. Heap strings can carry graphic tile codes from Phase 5 glyph modes.
; Editor-harvested control-range tiles are tagged with STRING_RAW_TILE in their
; attr byte, so tile $0D can draw raw while CHR$(13) (minted with DEFAULT_ATTR)
; still breaks lines. Plain text $20-$7E goes through OUTDO; untagged $0D stays a
; newline; all other controls/high bytes draw raw via chrout_glyph. The raw path
; still advances POSX one column and honors Z14 (output suppress) to match OUTDO.
; NOT used for literals/messages (those go through plain OUTDO; see @lit).
; Preserves X/Y. See docs/styled-strings.md §3.6.
; ----------------------------------------------------------------------------
styled_outc:
        bit     TEXT_ATTR
        bvs     @tagged_raw
        cmp     #$0D
        beq     @cr
        cmp     #$20
        bcc     @raw
        cmp     #$7F
        bcs     @raw
        jmp     OUTDO           ; normal text (tail call)
@cr:
        jsr     OUTDO           ; carriage return -> newline
        jmp     PRINTNULLS      ; (tail call)
@tagged_raw:
        pha
        lda     TEXT_ATTR
        and     #DISPLAY_ATTR_MASK
        sta     TEXT_ATTR
        pla
@raw:
        bit     Z14
        bmi     @suppressed     ; output suppressed: match OUTDO (no draw, no POSX)
        pha
        jsr     MONCOUT_GLYPH   ; raw tile draw (kernel; preserves X/Y)
        inc     POSX            ; one column per glyph, as OUTDO does for >=$20
        pla
@suppressed:
        rts
.endif

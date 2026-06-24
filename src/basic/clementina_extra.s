; ============================================================================
; clementina_extra.s - Clementina BASIC console glue (EXTRA segment)
; ----------------------------------------------------------------------------
; Thin thunks from BASIC's console contract into the Clementina kernel jump
; table. In the combined image the kernel lives at $0400 and owns the console.
; Keep these addresses in sync with src/kernel/kernel.inc / docs/memory-map.md.
; ============================================================================

.segment "EXTRA"
.export BASIC_COLD_START, MONRDKEY, MONRDKEY_NB, MONCOUT, MONRDLINE

KERN_CHROUT    = $0406
KERN_CHRIN     = $0409
KERN_GETKEY_NB = $040C
KERN_EDITKEY   = $0424

BASIC_COLD_START:
        jmp COLD_START

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

.ifdef STYLED_STRINGS
; ----------------------------------------------------------------------------
; STRPRT_STYLED - PRINT a string applying per-character attributes. Entered via
; an absolute jmp from STRPRT (print.s) with A = N (length) and INDEX = character
; data pointer; FREFAC has already run. Heap strings carry an attribute half at
; (data + N); program-text literals/messages do not, and print at DEFAULT_ATTR.
; Classify by data address: a heap string's data sits at or above the heap
; bottom, everything else (program text, messages, FBUFFR) below it. We compare
; against DEST, a snapshot of FRETOP that STRPRT takes *before* FREFAC: FREFAC
; frees a printed temp and raises FRETOP above it, but the temp keeps its bytes
; (including the attr half), so classifying against the post-free FRETOP would
; misread a styled temp (PRINT A$+B$, PRINT LEFT$(A$,3)) as a literal. FRETOP is
; snapshot (not STREND) because STREND is not yet initialized when the cold-start
; "BYTES FREE" message prints. Lives in the EXTRA segment so it never perturbs
; the CODE segment's tight branches. See docs/styled-strings.md §3.7/§5.
; ----------------------------------------------------------------------------
STRPRT_STYLED:
        pha                     ; save N
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
        sta     TEXT_ATTR
        lda     (INDEX),y       ; the character
        jsr     OUTDO
        iny
        cmp     #$0D
        bne     @hloop
        jsr     PRINTNULLS
        jmp     @hloop
@hdone:
        lda     #DEFAULT_ATTR   ; leave following output unstyled
        sta     TEXT_ATTR
        rts
@lit:
        lda     #DEFAULT_ATTR
        sta     TEXT_ATTR
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
        rts
.endif

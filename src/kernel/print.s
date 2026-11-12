; ============================================================================
; print.s - hex/string print helpers built on CHROUT, plus the boot banner
; ----------------------------------------------------------------------------
; Included by kernel.s into the single kernel translation unit (after
; kernel.inc).
; ============================================================================

.segment "KERNCODE"

; ----------------------------------------------------------------------------
; prhex - print the low nibble of A as a hex digit
; ----------------------------------------------------------------------------
prhex:
        and #$0F
        cmp #$0A
        bcc @digit
        adc #$06                ; +6 (+carry which is set) -> 'A'..'F'
@digit:
        adc #'0'
        jmp chrout

; ----------------------------------------------------------------------------
; prbyte - print A as two hex digits
; ----------------------------------------------------------------------------
prbyte:
        pha
        lsr
        lsr
        lsr
        lsr
        jsr prhex
        pla
        jmp prhex

; ----------------------------------------------------------------------------
; prstr - print the $00-terminated string pointed to by KPTR
; ----------------------------------------------------------------------------
prstr:
        ldy #$00
@loop:
        lda (KPTR),y
        beq @done
        jsr chrout
        iny
        bne @loop               ; strings under 256 bytes
@done:
        rts

; ----------------------------------------------------------------------------
; print_banner - draw the cold-start banner: the logo (a slanted sky blue,
; white and sky blue flag) with the title and copyright lines beside it. The
; banner is a $00-terminated string; bytes $01-$04 switch the TEXT_ATTR pen
; (banner_pens) and every other byte goes to chrout. Each flag row is reverse
; spaces (CHR_ALT: a solid cell, without using the cursor tiles at $F8-$FF)
; ending in an upper-left triangle.
; ----------------------------------------------------------------------------
PEN_WHITE    = $01              ; banner pen codes, index into banner_pens
PEN_WHITE_R  = $02
PEN_CYAN     = $03
PEN_CYAN_R   = $04
GLYPH_SLANT  = $A1              ; upper-left triangle: the flag's slanted end
GLYPH_COPY   = $9E              ; copyright sign

print_banner:
        ldy #$00
@loop:
        lda banner,y
        beq @done
        cmp #PEN_CYAN_R+1
        bcs @put
        tax
        lda banner_pens-1,x
        sta TEXT_ATTR
        bra @next
@put:
        jsr chrout
@next:
        iny
        bne @loop               ; banner under 256 bytes
@done:
        rts

; ----------------------------------------------------------------------------
; Read-only data
; ----------------------------------------------------------------------------
.segment "RODATA"
banner_pens:
        .byte ATTR_WHITE, ATTR_WHITE | MIA_VIDEO_ATTR_CHR_ALT
        .byte ATTR_CYAN,  ATTR_CYAN | MIA_VIDEO_ATTR_CHR_ALT
banner:
        .byte $0D
        .byte " ", PEN_CYAN_R, "       ", PEN_CYAN, GLYPH_SLANT
        .byte PEN_WHITE, "  CLEMENTINA V1.0 BASIC V2", $0D
        .byte " ", PEN_WHITE_R, "      ", PEN_WHITE, GLYPH_SLANT
        .byte "   ", GLYPH_COPY, " 2026 PACHISOFT", $0D
        .byte " ", PEN_CYAN_R, "     ", PEN_CYAN, GLYPH_SLANT
        .byte PEN_WHITE, "    ", GLYPH_COPY, " 1977 MICROSOFT BASIC"
        .byte $00               ; no CR: BASIC's cold start CRDO ends the line,
                                ; and the pen is back to white

; ============================================================================
; print.s - hex/string print helpers built on CHROUT, plus the boot banner
; ----------------------------------------------------------------------------
; Included by kernel.s into the single kernel translation unit (after
; kernel.inc).
; ============================================================================

.segment "CODE"

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
; print_banner - draw the cold-start banner.
; ----------------------------------------------------------------------------
print_banner:
        lda #ATTR_WHITE
        sta TEXT_ATTR
        lda #<banner
        sta KPTR
        lda #>banner
        sta KPTR+1
        jmp prstr

; ----------------------------------------------------------------------------
; Read-only data
; ----------------------------------------------------------------------------
.segment "RODATA"
banner:
        .byte $0D
        .byte "**** CLEMENTINA V1.0 BASIC V2 ****", $0D
        .byte "(C) 2026 PACHISOFT, 1977 MICROSOFT", $0D
        .byte $0D, $00

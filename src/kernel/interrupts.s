; ============================================================================
; interrupts.s - storage stubs and the minimal IRQ/NMI handlers
; ----------------------------------------------------------------------------
; Included by kernel.s into the single kernel translation unit (after
; kernel.inc).
; ============================================================================

.segment "CODE"

; ----------------------------------------------------------------------------
; load / save - storage stubs (mapped onto MIA FAT later)
; ----------------------------------------------------------------------------
load:
save:
        rts

; ----------------------------------------------------------------------------
; Interrupt handlers (minimal for milestone 1)
; ----------------------------------------------------------------------------
irq_handler:
        ; Acknowledge any pending MIA IRQ source and return. Real dispatch
        ; (input/SD/video events) arrives with the IRQ-driven console.
        pha
        lda IRQ_STATUS_L        ; read-to-clear
        pla
        rti

nmi_handler:
        rti

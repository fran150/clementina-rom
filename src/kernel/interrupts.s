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
; via_init - initialize the 65C22 for deterministic bank 0 and Timer 1 IRQs.
; Timer 1 runs in free-run mode with PB7 output disabled; the IRQ handler clears
; the T1 flag and uses it as a cursor blink tick only while CHRIN is polling.
; ----------------------------------------------------------------------------
via_init:
        stz VIA_ORA             ; external RAM bank 0
        lda #VIA_DDRA_BANK_BITS
        sta VIA_DDRA

        lda #$7F                ; disable and clear all VIA interrupt sources
        sta VIA_IER
        sta VIA_IFR

        lda VIA_ACR
        and #%00111111
        ora #VIA_ACR_T1_FREE_RUN
        sta VIA_ACR

        lda #<VIA_T1_RELOAD
        sta VIA_T1LL
        lda #>VIA_T1_RELOAD
        sta VIA_T1LH
        lda #<VIA_T1_RELOAD
        sta VIA_T1CL
        lda #>VIA_T1_RELOAD
        sta VIA_T1CH            ; load counter and start Timer 1

        lda #(VIA_IER_SET | VIA_IFR_T1)
        sta VIA_IER
        rts

; ----------------------------------------------------------------------------
; Interrupt handlers
; ----------------------------------------------------------------------------
irq_handler:
        pha
        phx
        phy

        ; Acknowledge any pending MIA IRQ source. VIA IRQs share the CPU IRQ
        ; line but are latched in the VIA, not MIA.
        lda IRQ_STATUS_L        ; read-to-clear

        lda VIA_IFR
        and #VIA_IFR_T1
        beq @done
        lda VIA_T1CL            ; clear the Timer 1 IFR bit

        lda CURSOR_BLINK_ACTIVE
        beq @done
        dec CURSOR_BLINK_COUNT
        bne @done
        lda #CURSOR_BLINK_TICKS
        sta CURSOR_BLINK_COUNT
        jsr cursor_toggle

@done:
        ply
        plx
        pla
        rti

nmi_handler:
        rti

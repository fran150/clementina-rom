; ============================================================================
; kernel.s - Clementina kernel
; ----------------------------------------------------------------------------
; Loaded by MIA into base RAM at the load base ($0400) and entered via the
; MIA-backed RESET vector. Provides the console (overlay text + input FIFO),
; a stable jump-table ABI, and (later) storage and BASIC/WozMon hand-off.
;
; Cold start enables the overlay text layer, clears the screen, prints the
; banner, then enters BASIC through the fixed kernel jump table.
;
; Console addressing: the overlay nametable is a fixed 40x25 grid in MIA RAM at
; $10080, reached through the preconfigured video index $B8. Because CFG now
; configures whichever index the window has selected, the console binds $B8 to
; window A and sets its current address (via CFG) to the cursor cell before each
; write. scroll_up uses kernel-reserved indexes $F0-$F3 for DMA copies.
; ============================================================================

.setcpu "65C02"

.include "kernel.inc"

.import BASIC_COLD_START

; ----------------------------------------------------------------------------
; Kernel zero page ($00F0-, see clementina.cfg)
; ----------------------------------------------------------------------------
.segment "KZEROPAGE": zeropage
KPTR:   .res 2          ; general 16-bit pointer (PRSTR source, etc.)
KTMP:   .res 2          ; scratch: computed overlay offset / address bytes
KCNT:   .res 2          ; 16-bit loop counter (fills / copies)
KCHR:   .res 1          ; character being printed by CHROUT

; ============================================================================
; Jump table - must land exactly on the KERN_* addresses from kernel.inc.
; The purpose of the jump table is to keep kernel address fixed even if the
; code changes in size.
; ============================================================================
.segment "JUMPTAB"
        jmp coldstart           ; KERN_COLDSTART
        jmp warmstart           ; KERN_WARMSTART
        jmp chrout              ; KERN_CHROUT
        jmp chrin               ; KERN_CHRIN
        jmp getkey_nb           ; KERN_GETKEY_NB
        jmp stop                ; KERN_STOP
        jmp clrscr              ; KERN_CLRSCR
        jmp prhex               ; KERN_PRHEX
        jmp prbyte              ; KERN_PRBYTE
        jmp prstr               ; KERN_PRSTR
        jmp load                ; KERN_LOAD
        jmp save                ; KERN_SAVE
        jmp editkey             ; KERN_EDITKEY
        jmp chrout_glyph        ; KERN_CHROUT_GLYPH

; Compile-time guard: confirm the table lines up with the published ABI.
.assert (* = KERN_BASE + $2A), error, "kernel jump table size/layout mismatch"

; ============================================================================
; Code
; ============================================================================
.segment "CODE"

; ----------------------------------------------------------------------------
; coldstart - reset entry point
; ----------------------------------------------------------------------------
coldstart:
        sei             ; disables interrupts
        cld             ; clears decimal mode
        
        ; Sets the stack pointer to $01FF (stack is empty)
        ldx #$FF        
        txs

        ; Install our real interrupt handlers into the MIA-backed vectors.
        ; MIA defaulted NMI/IRQ/BRK to the load base; replace them now.
        lda #<nmi_handler
        sta NMI_VEC
        lda #>nmi_handler
        sta NMI_VEC+1
        lda #<irq_handler
        sta IRQ_VEC
        lda #>irq_handler
        sta IRQ_VEC+1

        ; Clear kernel variable page state we rely on.
        stz CURSOR_X            ; cursor position on the screen
        stz CURSOR_Y
        lda #ATTR_WHITE         ; sets color white for the text
        sta TEXT_ATTR
        sta BASIC_DEFAULT_ATTR
        stz BASIC_STYLE_MASK
        stz LAST_KEY            ; 
        stz KEY_COUNT
        stz CURSOR_VISIBLE
        stz CURSOR_SAVE_CHR
        stz CURSOR_SAVE_ATTR
        stz EDIT_STATE          ; screen editor starts idle
        stz EDIT_MODE           ; glyph mode 0 (identity) at cold start
        stz EDIT_PAINT          ; not painting
        stz EDIT_CMD_PENDING    ; no ESC command pending
        stz CURSOR_BLINK_ACTIVE
        stz CURSOR_BLINK_COUNT

        jsr via_init

        ; Initializes video and clear screen
        jsr video_init
        jsr clrscr
        jsr print_banner

        cli             ; enable interrupts
        jmp BASIC_COLD_START

; ----------------------------------------------------------------------------
; warmstart - re-enter BASIC
; ----------------------------------------------------------------------------
warmstart:
        jmp BASIC_COLD_START

; ============================================================================
; Subsystem sources
; ----------------------------------------------------------------------------
; Each file is textually included into this one translation unit, so labels and
; kernel.inc constants resolve directly (no .import/.export between them). The
; include order sets CODE/RODATA emission order - keep it stable to preserve
; the image layout.
; ============================================================================
.include "video.s"
.include "console.s"
.include "input.s"
.include "editor.s"
.include "print.s"
.include "interrupts.s"

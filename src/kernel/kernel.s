; ============================================================================
; kernel.s - Clementina kernel
; ----------------------------------------------------------------------------
; Loaded by MIA into base RAM at the load base ($0400) and entered via the
; MIA-backed RESET vector. Provides the console (overlay text + input FIFO),
; a stable jump-table ABI, and (later) storage and BASIC/WozMon hand-off.
;
; Milestone 1: boot, enable the overlay text layer, clear the screen, print a
; banner, then run a polled CHRIN -> CHROUT echo loop.
;
; Console addressing: the overlay nametable is a fixed 40x25 grid in MIA RAM at
; $10080, reached through the preconfigured video index $B8. Because CFG now
; configures whichever index the window has selected, the console binds $B8 to
; window A and sets its current address (via CFG) to the cursor cell before each
; write. scroll_up additionally borrows general index 0 in window B as a read
; source. No fixed index is permanently reserved.
; ============================================================================

.setcpu "65C02"

.include "kernel.inc"

; ----------------------------------------------------------------------------
; Kernel zero page ($00F0-, see clementina.cfg)
; ----------------------------------------------------------------------------
.segment "ZEROPAGE"
KPTR:   .res 2          ; general 16-bit pointer (PRSTR source, etc.)
KTMP:   .res 2          ; scratch: computed overlay offset / address bytes
KCNT:   .res 2          ; 16-bit loop counter (fills / copies)

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

; Compile-time guard: confirm the table lines up with the published ABI.
.assert (* = KERN_BASE + $24), error, "kernel jump table size/layout mismatch"

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
        stz CURSOR_X
        stz CURSOR_Y
        stz TEXT_ATTR
        stz LAST_KEY
        stz KEY_COUNT

        ; Initializes video and clear screen
        jsr video_init
        jsr clrscr

        ; Writes the banner on start. It points low and high value of KPTR
        ; to the banner text and calls prstr function
        lda #<banner
        sta KPTR
        lda #>banner
        sta KPTR+1
        jsr prstr

        cli             ; enable interrupts

; ----------------------------------------------------------------------------
; warmstart - milestone-1 echo loop (will become the monitor/BASIC launcher)
; ----------------------------------------------------------------------------
warmstart:
echo_loop:
        jsr chrin               ; blocking read (also records debug state)
        jsr chrout              ; echo
        bra echo_loop

; ----------------------------------------------------------------------------
; video_init - enable the overlay text layer and request a full refresh
; NOTE: exact VIDEO_MODE/LAYER_ENABLE bits to be confirmed in the emulator.
; ----------------------------------------------------------------------------
video_init:
        ; Enable video output.
        lda #VIDEO_MODE_ENABLE
        sta CMD_PARAM1
        stz CMD_PARAM2
        stz CMD_PARAM3
        lda #CMD_VIDEO_SET_MODE
        sta CMD_TRIGGER

        ; Enable the overlay layer (stream one byte through index $81).
        lda #VIDX_LAYER_ENABLE
        sta IDXA_SELECT
        lda #LAYER_OVERLAY
        sta IDXA_PORT

        ; Make sure the client picks up the whole initial screen.
        lda #CMD_VIDEO_FULL_REFRESH
        sta CMD_TRIGGER
        rts

; ----------------------------------------------------------------------------
; clrscr - fill the overlay with spaces and home the cursor
; Binds the overlay index ($B8) to window A and streams from the base.
; ----------------------------------------------------------------------------
clrscr:
        lda #VIDX_OVERLAY_NT
        sta IDXA_SELECT
        lda #OVNT_ADDR_L
        ldx #OVNT_ADDR_M
        ldy #OVNT_ADDR_H
        jsr set_idxa_addr

        ; Write SCR_COLS*SCR_ROWS (1000) spaces; index $B8 auto-steps.
        lda #<(SCR_COLS * SCR_ROWS)
        sta KCNT
        lda #>(SCR_COLS * SCR_ROWS)
        sta KCNT+1
@fill:
        lda #' '
        sta IDXA_PORT
        lda KCNT
        bne @dec
        dec KCNT+1
@dec:
        dec KCNT
        lda KCNT
        ora KCNT+1
        bne @fill

        stz CURSOR_X
        stz CURSOR_Y
        rts

; ----------------------------------------------------------------------------
; chrout - write the character in A to the console at the cursor
; Handles CR ($0D = newline), LF ($0A = ignored), BS ($08), printable bytes.
; Preserves A/X/Y.
; ----------------------------------------------------------------------------
chrout:
        pha
        phx
        phy
        cmp #$0D
        beq @cr
        cmp #$0A
        beq @done               ; ignore LF; CR does the newline
        cmp #$08
        beq @bs

        ; Printable: aim the overlay index at the cursor cell and write.
        jsr cursor_to_idxa
        pla                     ; recover the character
        pha
        sta IDXA_PORT
        inc CURSOR_X
        lda CURSOR_X
        cmp #SCR_COLS
        bcc @done
        stz CURSOR_X            ; wrap to next line
        jsr newline
        bra @done

@cr:
        stz CURSOR_X
        jsr newline
        bra @done

@bs:
        lda CURSOR_X
        beq @done               ; keep it simple: don't back past column 0
        dec CURSOR_X
        jsr cursor_to_idxa
        lda #' '
        sta IDXA_PORT           ; erase the character under the cursor

@done:
        ply
        plx
        pla
        rts

; ----------------------------------------------------------------------------
; newline - advance cursor one row, scrolling at the bottom
; ----------------------------------------------------------------------------
newline:
        inc CURSOR_Y
        lda CURSOR_Y
        cmp #SCR_ROWS
        bcc @ok
        lda #SCR_ROWS-1
        sta CURSOR_Y
        jsr scroll_up
@ok:
        rts

; ----------------------------------------------------------------------------
; scroll_up - move rows 1..23 up one, blank the last row.
; Window B = general index 0 reading from overlay+SCR_COLS; window A = the
; overlay index writing from the overlay base.
; ----------------------------------------------------------------------------
scroll_up:
        ; Configure the scroll source (general index 0) in window B.
        lda #SCROLL_SRC_IDX
        sta IDXB_SELECT         ; bind index 0 -> CFG_IDXB_* now targets it
        lda #CFG_IDXB_STP_L
        sta CFG_SELECT
        lda #$01
        sta CFG_PORT
        lda #CFG_IDXB_STP_H
        sta CFG_SELECT
        stz CFG_PORT
        lda #CFG_IDXB_FLAGS
        sta CFG_SELECT
        lda #IXF_R_STP
        sta CFG_PORT
        lda #(OVNT_ADDR_L + SCR_COLS)
        ldx #OVNT_ADDR_M
        ldy #OVNT_ADDR_H
        jsr set_idxb_addr       ; setting the address refreshes IDXB_PORT too

        ; Destination: overlay index in window A, at the overlay base.
        lda #VIDX_OVERLAY_NT
        sta IDXA_SELECT
        lda #OVNT_ADDR_L
        ldx #OVNT_ADDR_M
        ldy #OVNT_ADDR_H
        jsr set_idxa_addr

        ; Copy (SCR_ROWS-1)*SCR_COLS = 960 bytes up one row.
        lda #<((SCR_ROWS-1) * SCR_COLS)
        sta KCNT
        lda #>((SCR_ROWS-1) * SCR_COLS)
        sta KCNT+1
@move:
        lda IDXB_PORT           ; read source (index 0 steps)
        sta IDXA_PORT           ; write dest (overlay index steps)
        lda KCNT
        bne @md
        dec KCNT+1
@md:
        dec KCNT
        lda KCNT
        ora KCNT+1
        bne @move

        ; Window A index now sits at the last row: blank SCR_COLS cells.
        ldx #SCR_COLS
        lda #' '
@blank:
        sta IDXA_PORT
        dex
        bne @blank
        rts

; ----------------------------------------------------------------------------
; cursor_to_idxa - bind the overlay index ($B8) to window A and set its current
; address to the cell for CURSOR_X/Y. Computes P = CURSOR_Y*40 + CURSOR_X and
; the 24-bit MIA address ($10080 + P).
; ----------------------------------------------------------------------------
cursor_to_idxa:
        lda #VIDX_OVERLAY_NT
        sta IDXA_SELECT         ; window A -> overlay index (CFG_IDXA_* targets it)

        ; P = CURSOR_Y * 40   (40 = 5 * 8; y<=24 so 5*y <= 120 fits 8 bits)
        lda CURSOR_Y
        asl
        asl                     ; 4y
        clc
        adc CURSOR_Y            ; 5y
        sta KTMP
        stz KTMP+1
        asl KTMP
        rol KTMP+1              ; 10y
        asl KTMP
        rol KTMP+1              ; 20y
        asl KTMP
        rol KTMP+1              ; 40y
        ; P += CURSOR_X
        lda KTMP
        clc
        adc CURSOR_X
        sta KTMP
        lda KTMP+1
        adc #$00
        sta KTMP+1
        ; MIA address = $010000 + ($0080 + P). $0080+P <= $0467, so the high
        ; byte is always OVNT_ADDR_H ($01). Reuse KTMP for low/mid.
        lda KTMP
        clc
        adc #OVNT_ADDR_L        ; + $80
        sta KTMP                ; address low
        lda KTMP+1
        adc #OVNT_ADDR_M        ; + carry
        sta KTMP+1              ; address mid
        lda KTMP                ; A = low
        ldx KTMP+1              ; X = mid
        ldy #OVNT_ADDR_H        ; Y = high
        jsr set_idxa_addr
        rts

; ----------------------------------------------------------------------------
; set_idxa_addr / set_idxb_addr - set the current address of the index selected
; in window A / window B. In: A = addr low, X = addr mid, Y = addr high.
; The matching index must already be bound to the window.
; ----------------------------------------------------------------------------
set_idxa_addr:
        pha
        lda #CFG_IDXA_ADDR_L
        sta CFG_SELECT
        pla
        sta CFG_PORT
        lda #CFG_IDXA_ADDR_M
        sta CFG_SELECT
        stx CFG_PORT
        lda #CFG_IDXA_ADDR_H
        sta CFG_SELECT
        sty CFG_PORT
        rts

set_idxb_addr:
        pha
        lda #CFG_IDXB_ADDR_L
        sta CFG_SELECT
        pla
        sta CFG_PORT
        lda #CFG_IDXB_ADDR_M
        sta CFG_SELECT
        stx CFG_PORT
        lda #CFG_IDXB_ADDR_H
        sta CFG_SELECT
        sty CFG_PORT
        rts

; ----------------------------------------------------------------------------
; chrin - blocking read of one text byte from the MIA FIFO -> A
; Records LAST_KEY / KEY_COUNT for easy verification in the emulator's memory
; window before the video client is attached.
; ----------------------------------------------------------------------------
chrin:
        jsr getkey_nb
        bcc chrin               ; nothing yet, keep polling
        sta LAST_KEY
        inc KEY_COUNT
        rts

; ----------------------------------------------------------------------------
; getkey_nb - non-blocking read. Returns C=1 and A=char if available, else C=0.
; ----------------------------------------------------------------------------
getkey_nb:
        lda INPUT_STATUS
        and #INPUT_STATUS_TEXT_READY
        beq @none
        lda INPUT_CHAR
        sec
        rts
@none:
        clc
        rts

; ----------------------------------------------------------------------------
; stop - ISCNTC: report whether a Ctrl-C (break) is pending. Z=1 if break.
; Milestone-1 placeholder: never reports a break. Real break handling lands
; with BASIC.
; ----------------------------------------------------------------------------
stop:
        lda #$01                ; Z=0 -> "no break"
        rts

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

; ----------------------------------------------------------------------------
; Read-only data
; ----------------------------------------------------------------------------
.segment "RODATA"
banner:
        .byte "CLEMENTINA KERNEL 0.1", $0D, $0D
        .byte "READY.", $0D, $00

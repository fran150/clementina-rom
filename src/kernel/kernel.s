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
; write. scroll_up uses kernel-reserved indexes $F0-$F3 for DMA copies.
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
        lda #ATTR_WHITE
        sta TEXT_ATTR
        stz LAST_KEY
        stz KEY_COUNT

        ; Initializes video and clear screen
        jsr video_init
        jsr clrscr

        jsr print_banner

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
; video_load_palettes - load vibrant RGB565 palette banks 0-7.
; Palette 0 is the default console palette: blue transparent/background slot
; and white foreground text. The other banks provide convenient text colors.
; ----------------------------------------------------------------------------
video_load_palettes:
        lda #<palette_data
        sta KPTR
        lda #>palette_data
        sta KPTR+1
        lda #VIDX_PALETTE_0
        sta KTMP
@bank:
        lda KTMP
        sta IDXA_SELECT
        ldy #$00
@byte:
        lda (KPTR),y
        sta IDXA_PORT
        iny
        cpy #$10
        bne @byte

        clc
        lda KPTR
        adc #$10
        sta KPTR
        bcc @no_carry
        inc KPTR+1
@no_carry:
        inc KTMP
        lda KTMP
        cmp #(VIDX_PALETTE_0 + PALETTE_COUNT)
        bne @bank
        rts

; ----------------------------------------------------------------------------
; video_init - configure palette/font state, enable overlay, request refresh
; ----------------------------------------------------------------------------
video_init:
        jsr video_load_palettes

        ; Use MIA's default PETSCII-compatible 1bpp font in CHR bank 0 for all
        ; tile consumers. The overlay plane selector uses plane 1, the
        ; lowercase/uppercase charset.
        lda #VIDX_BANK_SELECT
        sta IDXA_SELECT
        lda #VIDEO_CHR_BANK_DEFAULT
        sta IDXA_PORT           ; background bank
        sta IDXA_PORT           ; background alt bank
        sta IDXA_PORT           ; overlay bank
        sta IDXA_PORT           ; overlay alt bank
        sta IDXA_PORT           ; sprite bank

        lda #VIDX_CHR_1BPP
        sta IDXA_SELECT
        lda #CHR_1BPP_BANK0_MASK
        sta IDXA_PORT
        lda #CHR_1BPP_PLANES_OVERLAY1
        sta IDXA_PORT

        jsr init_scroll_indexes

        ; Palette 0 color 0 is the blue screen backdrop.
        lda #VIDX_BACKDROP_COLOR
        sta IDXA_SELECT
        lda #BACKDROP_BLUE
        sta IDXA_PORT

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
; init_scroll_indexes - reserve $F0-$F3 as fixed DMA source/destination pairs.
; ----------------------------------------------------------------------------
init_scroll_indexes:
        lda #KIDX_SCROLL_NT_SRC
        sta IDXA_SELECT
        lda #(OVNT_ADDR_L + SCR_COLS)
        ldx #OVNT_ADDR_M
        ldy #OVNT_ADDR_H
        jsr set_idxa_addr
        lda #<(OVNT_ADDR_L + (SCR_ROWS * SCR_COLS))
        ldx #(OVNT_ADDR_M + >(OVNT_ADDR_L + (SCR_ROWS * SCR_COLS)))
        ldy #OVNT_ADDR_H
        jsr set_idxa_limit

        lda #KIDX_SCROLL_NT_DST
        sta IDXA_SELECT
        lda #OVNT_ADDR_L
        ldx #OVNT_ADDR_M
        ldy #OVNT_ADDR_H
        jsr set_idxa_addr

        lda #KIDX_SCROLL_ATTR_SRC
        sta IDXA_SELECT
        lda #(OVATTR_ADDR_L + SCR_COLS)
        ldx #OVATTR_ADDR_M
        ldy #OVATTR_ADDR_H
        jsr set_idxa_addr
        lda #<(OVATTR_ADDR_L + (SCR_ROWS * SCR_COLS))
        ldx #(OVATTR_ADDR_M + >(OVATTR_ADDR_L + (SCR_ROWS * SCR_COLS)))
        ldy #OVATTR_ADDR_H
        jsr set_idxa_limit

        lda #KIDX_SCROLL_ATTR_DST
        sta IDXA_SELECT
        lda #OVATTR_ADDR_L
        ldx #OVATTR_ADDR_M
        ldy #OVATTR_ADDR_H
        jsr set_idxa_addr
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

        lda #VIDX_OVERLAY_ATTR
        sta IDXA_SELECT
        lda #OVATTR_ADDR_L
        ldx #OVATTR_ADDR_M
        ldy #OVATTR_ADDR_H
        jsr set_idxa_addr

        ; Match every cleared cell to the current text color.
        lda #<(SCR_COLS * SCR_ROWS)
        sta KCNT
        lda #>(SCR_COLS * SCR_ROWS)
        sta KCNT+1
@attr_fill:
        lda TEXT_ATTR
        sta IDXA_PORT
        lda KCNT
        bne @attr_dec
        dec KCNT+1
@attr_dec:
        dec KCNT
        lda KCNT
        ora KCNT+1
        bne @attr_fill

        stz CURSOR_X
        stz CURSOR_Y
        rts

; ----------------------------------------------------------------------------
; chrout - write the character in A to the console at the cursor
; Handles CR ($0D = newline), LF ($0A = ignored), BS ($08), printable bytes.
; Preserves A/X/Y.
; ----------------------------------------------------------------------------
chrout:
        sta KCHR
        pha
        phx
        phy
        cmp #$0D
        beq @cr
        cmp #$0A
        beq @done               ; ignore LF; CR does the newline
        cmp #$08
        beq @bs

        ; Printable: aim the overlay indexes at the cursor cell and write the
        ; tile code plus its palette attribute.
        jsr cursor_to_idxa
        lda KCHR
        jsr char_to_tile
        sta IDXA_PORT
        jsr cursor_attr_to_idxa
        lda TEXT_ATTR
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
        jsr cursor_attr_to_idxa
        lda TEXT_ATTR
        sta IDXA_PORT

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
; Uses MIA DMA via CMD_COPY_INDEXES. A zero byte count copies from source
; current address up to source limit address, without moving either index.
; ----------------------------------------------------------------------------
scroll_up:
        lda #KIDX_SCROLL_NT_SRC
        ldx #KIDX_SCROLL_NT_DST
        jsr dma_copy_indexes

        ; Blank the last nametable row.
        lda #VIDX_OVERLAY_NT
        sta IDXA_SELECT
        lda #<(OVNT_ADDR_L + ((SCR_ROWS-1) * SCR_COLS))
        ldx #(OVNT_ADDR_M + >(OVNT_ADDR_L + ((SCR_ROWS-1) * SCR_COLS)))
        ldy #OVNT_ADDR_H
        jsr set_idxa_addr
        ldx #SCR_COLS
        lda #' '
@blank:
        sta IDXA_PORT
        dex
        bne @blank

        ; Scroll matching overlay attributes so colored text keeps its palette.
        lda #KIDX_SCROLL_ATTR_SRC
        ldx #KIDX_SCROLL_ATTR_DST
        jsr dma_copy_indexes

        lda #VIDX_OVERLAY_ATTR
        sta IDXA_SELECT
        lda #<(OVATTR_ADDR_L + ((SCR_ROWS-1) * SCR_COLS))
        ldx #(OVATTR_ADDR_M + >(OVATTR_ADDR_L + ((SCR_ROWS-1) * SCR_COLS)))
        ldy #OVATTR_ADDR_H
        jsr set_idxa_addr
        ldx #SCR_COLS
        lda TEXT_ATTR
@attr_blank:
        sta IDXA_PORT
        dex
        bne @attr_blank
        rts

dma_copy_indexes:
        sta CMD_PARAM1
        txa
        sta CMD_PARAM2
        stz CMD_PARAM3          ; zero = copy until source index limit
        lda #CMD_COPY_INDEXES
        sta CMD_TRIGGER
wait_cmd_dma:
        lda STATUS_L
        and #(MIA_STAT_CMD_RUNNING | MIA_STAT_DMA_RUNNING)
        bne wait_cmd_dma
        rts

; ----------------------------------------------------------------------------
; cursor_to_idxa - bind the overlay index ($B8) to window A and set its current
; address to the cell for CURSOR_X/Y. Computes P = CURSOR_Y*40 + CURSOR_X and
; the 24-bit MIA address ($10080 + P).
; ----------------------------------------------------------------------------
cursor_to_idxa:
        lda #VIDX_OVERLAY_NT
        sta IDXA_SELECT         ; window A -> overlay index (CFG_IDXA_* targets it)
        jsr cursor_offset_to_ktmp
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

cursor_attr_to_idxa:
        lda #VIDX_OVERLAY_ATTR
        sta IDXA_SELECT
        jsr cursor_offset_to_ktmp
        lda KTMP
        clc
        adc #OVATTR_ADDR_L
        sta KTMP
        lda KTMP+1
        adc #OVATTR_ADDR_M
        sta KTMP+1
        lda KTMP
        ldx KTMP+1
        ldy #OVATTR_ADDR_H
        jsr set_idxa_addr
        rts

cursor_offset_to_ktmp:
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
        rts

; ----------------------------------------------------------------------------
; set_idxa_addr / set_idxa_limit - set the current/limit address of the index
; selected in window A. In: A = addr low, X = addr mid, Y = addr high.
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

set_idxa_limit:
        pha
        lda #CFG_IDXA_LIMIT_L
        sta CFG_SELECT
        pla
        sta CFG_PORT
        lda #CFG_IDXA_LIMIT_M
        sta CFG_SELECT
        stx CFG_PORT
        lda #CFG_IDXA_LIMIT_H
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
; char_to_tile - convert ASCII-ish text to the C64-style screen codes in MIA's
; lowercase/uppercase font plane. Uppercase, digits, punctuation, and spaces are
; already usable as-is; lowercase a-z live at screen codes 1-26.
; ----------------------------------------------------------------------------
char_to_tile:
        cmp #'a'
        bcc @done
        cmp #'z'+1
        bcs @done
        sec
        sbc #$60
        rts
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
; Eight RGB565 colors per palette, little-endian. For 1bpp overlay text,
; color index 0 is transparent/backdrop and color index 1 is the glyph color.
palette_data:
        ; palette 0: default console (blue backdrop, white text)
        .byte $1F,$1A, $FF,$FF, $00,$00, $00,$F8
        .byte $60,$FC, $C0,$FE, $E0,$07, $5F,$07
        ; palette 1: red foreground
        .byte $1F,$1A, $00,$F8, $FF,$FF, $60,$FC
        .byte $C0,$FE, $E0,$07, $5F,$07, $7F,$FA
        ; palette 2: orange foreground
        .byte $1F,$1A, $60,$FC, $FF,$FF, $00,$F8
        .byte $C0,$FE, $E0,$07, $5F,$07, $7F,$FA
        ; palette 3: yellow foreground
        .byte $1F,$1A, $C0,$FE, $FF,$FF, $00,$F8
        .byte $60,$FC, $E0,$07, $5F,$07, $7F,$FA
        ; palette 4: green foreground
        .byte $1F,$1A, $E0,$07, $FF,$FF, $00,$F8
        .byte $60,$FC, $C0,$FE, $5F,$07, $7F,$FA
        ; palette 5: cyan foreground
        .byte $1F,$1A, $5F,$07, $FF,$FF, $00,$F8
        .byte $60,$FC, $C0,$FE, $E0,$07, $7F,$FA
        ; palette 6: magenta foreground
        .byte $1F,$1A, $7F,$FA, $FF,$FF, $00,$F8
        .byte $60,$FC, $C0,$FE, $E0,$07, $5F,$07
        ; palette 7: bright blue-white foreground
        .byte $1F,$1A, $FF,$6A, $FF,$FF, $00,$F8
        .byte $60,$FC, $C0,$FE, $E0,$07, $5F,$07

banner:
        .byte $0D
        .byte "**** CLEMENTINA V1.0 BASIC V2 ****", $0D
        .byte "(C) 2026 PACHISOFT, 1977 MICROSOFT", $0D
        .byte $0D
        .byte "READY.", $0D, $00

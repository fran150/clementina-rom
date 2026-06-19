; ============================================================================
; kernel.inc - Clementina kernel shared equates
; ----------------------------------------------------------------------------
; Included by the kernel itself and by any client (BASIC, WozMon, user
; programs) that needs to call kernel services or touch MIA directly.
;
; Everything here is *contract*: addresses and constants other code depends
; on. Keep it in sync with docs/memory-map.md.
; ============================================================================

; ----------------------------------------------------------------------------
; MIA register block ($FFE0-$FFFF)
; ----------------------------------------------------------------------------
IDXA_PORT          = $FFE0     ; index window A data port
IDXA_SELECT        = $FFE1     ; index window A descriptor selector
CFG_SELECT         = $FFE2     ; configuration field selector
CFG_PORT           = $FFE3     ; configuration field data port
IDXB_PORT          = $FFE4     ; index window B data port
IDXB_SELECT        = $FFE5     ; index window B descriptor selector
CMD_PARAM1         = $FFE6     ; parameter 1 for command
CMD_PARAM2         = $FFE7     ; parameter 2 for command
CMD_PARAM3         = $FFE8     ; parameter 3 for command
CMD_TRIGGER        = $FFE9     ; write command id here to queue it
STATUS_L           = $FFEA     ; status register
STATUS_H           = $FFEB
ERROR_L            = $FFEC     ; read-to-pop error queue
ERROR_H            = $FFED
IRQ_MASK_L         = $FFEE     ; Mask to enable / disable IRQs
IRQ_MASK_H         = $FFEF
IRQ_STATUS_L       = $FFF0     ; read-to-clear (clears all pending IRQ bits)
IRQ_STATUS_H       = $FFF1     ; passive read; sample before $FFF0
INPUT_STATUS       = $FFF2     ; input status
INPUT_CHAR         = $FFF3     ; read-to-pop text FIFO ($00 when empty)
INPUT_CHAR_COUNT   = $FFF4     ; characters in input fifo queue
NMI_VEC            = $FFFA     ; MIA-backed 6502 NMI vector
RESET_VEC          = $FFFC     ; MIA-backed 6502 RESET vector
IRQ_VEC            = $FFFE     ; MIA-backed 6502 IRQ/BRK vector

; INPUT_STATUS bits
INPUT_STATUS_TEXT_READY      = %00000001
INPUT_STATUS_SOURCE_CONSOLE  = %00100000
INPUT_STATUS_SOURCE_WIFI     = %01000000
INPUT_STATUS_SOURCE_USB_HOST = %10000000

; ----------------------------------------------------------------------------
; MIA configuration field ids (CFG_SELECT values).
; Ids $00-$0F configure the index currently selected in window A; $10-$1F the
; index selected in window B. Bind an index with IDXA_SELECT/IDXB_SELECT first,
; then write its fields through CFG_SELECT/CFG_PORT. Writing a current-address
; byte refreshes that window's data port from the new address, so a read right
; after repositioning the index returns the new byte (no re-select).
; ----------------------------------------------------------------------------
CFG_IDXA_ADDR_L    = $00
CFG_IDXA_ADDR_M    = $01
CFG_IDXA_ADDR_H    = $02
CFG_IDXA_LIMIT_L   = $06
CFG_IDXA_LIMIT_M   = $07
CFG_IDXA_LIMIT_H   = $08
CFG_IDXA_STP_L     = $09
CFG_IDXA_STP_H     = $0A
CFG_IDXA_FLAGS     = $0B
CFG_IDXB_ADDR_L    = $10
CFG_IDXB_ADDR_M    = $11
CFG_IDXB_ADDR_H    = $12
CFG_IDXB_LIMIT_L   = $16
CFG_IDXB_LIMIT_M   = $17
CFG_IDXB_LIMIT_H   = $18
CFG_IDXB_STP_L     = $19
CFG_IDXB_STP_H     = $1A
CFG_IDXB_FLAGS     = $1B

; STATUS_L bits
MIA_STAT_CMD_RUNNING = %00000100
MIA_STAT_DMA_RUNNING = %00001000

; Kernel/system-reserved MIA index descriptors. User code must leave $F0-$FF
; alone while using kernel services.
KIDX_SCROLL_NT_SRC   = $F0
KIDX_SCROLL_NT_DST   = $F1
KIDX_SCROLL_ATTR_SRC = $F2
KIDX_SCROLL_ATTR_DST = $F3

; Index descriptor flag bits
IXF_R_STP          = %00000001 ; step after read
IXF_W_STP          = %00000010 ; step after write
IXF_DIR_BACK       = %00000100 ; step direction backward
IXF_WRAP           = %00001000 ; wrap at range limits
IXF_WRAP_IRQ       = %00010000 ; raise wrap IRQ

; ----------------------------------------------------------------------------
; MIA commands (CMD_TRIGGER values) used by the kernel
; ----------------------------------------------------------------------------
CMD_IDX_RESET_A    = $00
CMD_IDX_RESET_B    = $01
CMD_COPY_INDEXES   = $10
CMD_VIDEO_FULL_REFRESH = $42
CMD_VIDEO_SET_MODE = $43

; ----------------------------------------------------------------------------
; MIA video: indexes and overlay text layer
; ----------------------------------------------------------------------------
VIDX_RENDER_CONTROL = $80      ; streams the 32-byte render control page ($20..)
VIDX_LAYER_ENABLE   = $81      ; 1 byte: background/overlay/sprite enables
VIDX_BANK_SELECT    = $85      ; 5 bytes: bg, bg alt, overlay, overlay alt, sprite
VIDX_CHR_1BPP       = $86      ; 2 bytes: CHR_1BPP_MASK, CHR_1BPP_PLANES
VIDX_BACKDROP_COLOR = $87      ; 1 byte: palette/color selector
VIDX_PALETTE_0      = $90      ; first of 16 palette-bank indexes
PALETTE_COUNT       = 8        ; kernel loads palette banks 0-7
VIDX_OVERLAY_NT     = $B8      ; overlay nametable, 1000 bytes @ $10080
VIDX_OVERLAY_ATTR   = $B9      ; overlay attributes, 1000 bytes @ $10468

; Overlay nametable base, as a 24-bit MIA RAM address ($10080)
OVNT_ADDR_L         = $80
OVNT_ADDR_M         = $00
OVNT_ADDR_H         = $01

; Overlay attribute base, as a 24-bit MIA RAM address ($10468)
OVATTR_ADDR_L       = $68
OVATTR_ADDR_M       = $04
OVATTR_ADDR_H       = $01

; LAYER_ENABLE bits (bit0 background, bit1 overlay, bit2 sprite)
LAYER_BACKGROUND    = %00000001
LAYER_OVERLAY       = %00000010
LAYER_SPRITE        = %00000100

; VIDEO_MODE: bit0 = video enable.
VIDEO_MODE_ENABLE   = %00000001

; MIA split-loads the selected font: ASCII text -> CHR bank 0 plane 0 (primary
; overlay bank), graphics/line set -> CHR bank 1 plane 0 (alternate overlay
; bank). The overlay renders plane 0; per-cell CHR_ALT selects the text bank (0)
; or the graphics bank (1). Tile code == ASCII codepoint in the text bank.
VIDEO_CHR_BANK_DEFAULT   = $00         ; text / primary bank (also bg and sprite)
VIDEO_CHR_BANK_GRAPHICS  = $01         ; alternate overlay bank: graphics / line set
CHR_1BPP_BANKS_TEXT_GFX  = %00000011   ; CHR banks 0 and 1 decoded as 1bpp
CHR_1BPP_PLANES_OVERLAY0 = %00000000   ; overlay 1bpp plane selector = plane 0

; Overlay text attributes. Bits 0-3 select the palette bank; in 1bpp text
; glyph pixels use color index 1 from that bank and color index 0 is transparent.
ATTR_WHITE          = $00
ATTR_RED            = $01
ATTR_ORANGE         = $02
ATTR_YELLOW         = $03
ATTR_GREEN          = $04
ATTR_CYAN           = $05
ATTR_MAGENTA        = $06
ATTR_BLUE_WHITE     = $07

; BACKDROP_COLOR selector: bits 0-2 = color index, bits 3-6 = palette bank.
BACKDROP_BLUE       = $00

; Text screen geometry (overlay is a fixed 40x25 screen-space grid)
SCR_COLS            = 40
SCR_ROWS            = 25

; ----------------------------------------------------------------------------
; Kernel jump table - the stable ABI. Anchored at the load base ($0400).
; Callers JSR these; internal routine addresses may move freely.
; ----------------------------------------------------------------------------
KERN_BASE          = $0400
KERN_COLDSTART     = KERN_BASE + $00   ; reset entry (MIA points RESET here)
KERN_WARMSTART     = KERN_BASE + $03   ; re-enter the system
KERN_CHROUT        = KERN_BASE + $06   ; A = char -> console
KERN_CHRIN         = KERN_BASE + $09   ; blocking read -> A
KERN_GETKEY_NB     = KERN_BASE + $0C   ; non-blocking; C=1 if A holds a char
KERN_STOP          = KERN_BASE + $0F   ; ISCNTC: Z=1 if break (Ctrl-C) pending
KERN_CLRSCR        = KERN_BASE + $12   ; clear screen, home cursor
KERN_PRHEX         = KERN_BASE + $15   ; A low nibble -> hex digit via CHROUT
KERN_PRBYTE        = KERN_BASE + $18   ; A -> two hex digits via CHROUT
KERN_PRSTR         = KERN_BASE + $1B   ; print $00-terminated string at (KPTR)
KERN_LOAD          = KERN_BASE + $1E   ; load (stub for now)
KERN_SAVE          = KERN_BASE + $21   ; save (stub for now)

; ----------------------------------------------------------------------------
; Kernel variable page ($0300-$03FF). See docs/memory-map.md.
; ----------------------------------------------------------------------------
KVARS              = $0300
CURSOR_X           = KVARS + $00   ; 0..SCR_COLS-1
CURSOR_Y           = KVARS + $01   ; 0..SCR_ROWS-1
TEXT_ATTR          = KVARS + $02   ; overlay attribute/color for new cells
LAST_KEY           = KVARS + $03   ; debug: last byte returned by CHRIN
KEY_COUNT          = KVARS + $04   ; debug: count of bytes read by CHRIN
CINV               = KVARS + $05   ; reserved: redirectable CHRIN vector (2)
COUTV              = KVARS + $07   ; reserved: redirectable CHROUT vector (2)
CURSOR_VISIBLE     = KVARS + $09   ; nonzero when cursor glyph is drawn
CURSOR_SAVE_CHR    = KVARS + $0A   ; character under visible cursor
CURSOR_SAVE_ATTR   = KVARS + $0B   ; attribute under visible cursor

; Cursor glyph printed into the overlay while waiting for input.
CURSOR_TILE        = '_'

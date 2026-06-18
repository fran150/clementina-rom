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
CFG_IDXA_STP_L     = $09
CFG_IDXA_STP_H     = $0A
CFG_IDXA_FLAGS     = $0B
CFG_IDXB_ADDR_L    = $10
CFG_IDXB_ADDR_M    = $11
CFG_IDXB_ADDR_H    = $12
CFG_IDXB_STP_L     = $19
CFG_IDXB_STP_H     = $1A
CFG_IDXB_FLAGS     = $1B

; General-purpose index the console borrows as the scroll source (bound to
; window B only during scroll_up). Index $B8 (the overlay nametable) is the
; primary console write index, bound to window A.
SCROLL_SRC_IDX     = $00

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
CMD_VIDEO_FULL_REFRESH = $42
CMD_VIDEO_SET_MODE = $43

; ----------------------------------------------------------------------------
; MIA video: indexes and overlay text layer
; ----------------------------------------------------------------------------
VIDX_RENDER_CONTROL = $80      ; streams the 32-byte render control page ($20..)
VIDX_LAYER_ENABLE   = $81      ; 1 byte: background/overlay/sprite enables
VIDX_OVERLAY_NT     = $B8      ; overlay nametable, 1000 bytes @ $10080
VIDX_OVERLAY_ATTR   = $B9      ; overlay attributes, 1000 bytes @ $10468

; Overlay nametable base, as a 24-bit MIA RAM address ($10080)
OVNT_ADDR_L         = $80
OVNT_ADDR_M         = $00
OVNT_ADDR_H         = $01

; LAYER_ENABLE bits (bit0 background, bit1 overlay, bit2 sprite)
LAYER_BACKGROUND    = %00000001
LAYER_OVERLAY       = %00000010
LAYER_SPRITE        = %00000100

; VIDEO_MODE: bit0 = video enable (verify exact bits against emulator/firmware)
VIDEO_MODE_ENABLE   = %00000001

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
TEXT_ATTR          = KVARS + $02   ; reserved: overlay attribute/color
LAST_KEY           = KVARS + $03   ; debug: last byte returned by CHRIN
KEY_COUNT          = KVARS + $04   ; debug: count of bytes read by CHRIN
CINV               = KVARS + $05   ; reserved: redirectable CHRIN vector (2)
COUTV              = KVARS + $07   ; reserved: redirectable CHROUT vector (2)

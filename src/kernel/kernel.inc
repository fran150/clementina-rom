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
; 65C22 VIA in I/O slot 0 ($C000-$C3FF). Registers mirror every 16 bytes.
; Port A drives the external RAM bank select; Timer 1 provides the kernel tick.
; ----------------------------------------------------------------------------
VIA_BASE            = $C000
VIA_ORB             = VIA_BASE + $00
VIA_ORA             = VIA_BASE + $01
VIA_DDRB            = VIA_BASE + $02
VIA_DDRA            = VIA_BASE + $03
VIA_T1CL            = VIA_BASE + $04
VIA_T1CH            = VIA_BASE + $05
VIA_T1LL            = VIA_BASE + $06
VIA_T1LH            = VIA_BASE + $07
VIA_ACR             = VIA_BASE + $0B
VIA_IFR             = VIA_BASE + $0D
VIA_IER             = VIA_BASE + $0E

VIA_DDRA_BANK_BITS  = %00011111 ; PA0-PA4 select one of 32 extended RAM banks
VIA_ACR_T1_FREE_RUN = %01000000 ; Timer 1 free-runs, PB7 output disabled
VIA_IFR_T1          = %01000000
VIA_IER_SET         = %10000000

; At 1 MHz PHI2, 62500 cycles gives a 62.5 ms tick; eight ticks gives a
; classic half-second cursor blink. If PHI2 changes, the blink follows it.
VIA_T1_RELOAD       = 62500
CURSOR_BLINK_TICKS  = 8

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
; Console control codes. CHROUT acts on these instead of drawing a glyph.
; Cursor moves and HOME use PETSCII values so MIA's keyboard decode table
; (usage -> FIFO byte) and the console agree on one set; CR/LF/BS/FF reuse
; their ASCII codes. Keep in sync with inputDecodeKeyUsage in the MIA firmware.
; ----------------------------------------------------------------------------
CHR_BS              = $08      ; backspace: cursor left one cell and erase
CHR_LF              = $0A      ; line feed: ignored (CR does the newline)
CHR_ESC             = $1B      ; editor: ESC command prefix (Phase 5 styling)
CHR_FF              = $0C      ; form feed: clear screen and home
CHR_CR              = $0D      ; carriage return: newline
CHR_CRSR_DOWN       = $11      ; cursor down one row
CHR_HOME            = $13      ; cursor to top-left
CHR_CRSR_RIGHT      = $1D      ; cursor right one cell
CHR_CRSR_UP         = $91      ; cursor up one row
CHR_CRSR_LEFT       = $9D      ; cursor left one cell
CHR_DEL_FWD         = $7F      ; editor: delete the char at the cursor (close gap)
CHR_INSERT          = $94      ; editor: open a gap at the cursor (insert space)

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
KERN_EDITKEY       = KERN_BASE + $24   ; screen editor: next char of edited line
KERN_CHROUT_GLYPH  = KERN_BASE + $27   ; A = tile -> console as a raw glyph (no ctrl)

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

; Logical-line link table: one byte per screen row (SCR_ROWS bytes). Bit 7 set
; means the row STARTS a logical line; clear means it continues the row above
; (created by line wrap). The screen editor walks this table to harvest the whole
; logical line under the cursor on RETURN. Maintained by clrscr / CHROUT / scroll.
LINE_LINK          = KVARS + $0C   ; .. KVARS + $0C + SCR_ROWS-1  ($030C-$0324)

LINK_START         = $80           ; LINE_LINK value for a logical-line start

; Screen-editor state. The editor edits overlay cells directly (the screen is the
; buffer) and on RETURN harvests the logical line under the cursor into EDIT_BUF,
; which KERN_EDITKEY then doles to BASIC's line input one byte at a time.
EDIT_BUF_SIZE      = 80                        ; EDIT_BUF capacity (two full 40-column rows)
EDIT_BUF           = KVARS + $0C + SCR_ROWS    ; harvested line ($0325, EDIT_BUF_SIZE bytes)
EDIT_LEN           = EDIT_BUF + EDIT_BUF_SIZE  ; harvested length after trailing-space trim
EDIT_IDX           = EDIT_LEN + 1              ; dole-out read index
EDIT_STATE         = EDIT_LEN + 2             ; 0 = idle (run editor), nonzero = doling a line
EDIT_START_X       = EDIT_LEN + 3             ; cursor col where the current input began
EDIT_START_Y       = EDIT_LEN + 4             ; cursor row where the current input began
EDIT_RS            = EDIT_LEN + 5             ; harvest scratch: logical-line start row
EDIT_RE            = EDIT_LEN + 6             ; harvest scratch: logical-line end row
EDIT_CP            = EDIT_LEN + 7             ; insert/delete scratch: cursor pos within line
EDIT_LL            = EDIT_LEN + 8             ; insert/delete scratch: logical-line cell count
CURSOR_BLINK_ACTIVE = KVARS + $7E  ; nonzero when Timer 1 may toggle the cursor
CURSOR_BLINK_COUNT  = KVARS + $7F  ; ticks until the next cursor toggle
; Per-cell attributes of the harvested line, parallel to EDIT_BUF (styled
; strings, see docs/styled-strings.md). EDIT_ATTR_BUF[k] is the attribute of
; EDIT_BUF[k], which BASIC's INLIN stores 1:1 at INPUTBUFFER[k]. 80 bytes.
EDIT_ATTR_BUF       = KVARS + $80   ; $0380-$03CF

; Phase 5 editor styling state (charset/keyboard glyph entry; see
; docs/phase5-charset-keyboard.md). Lives in the free KVARS tail $03D0-$03FF.
EDIT_MODE          = KVARS + $D0   ; glyph mode 0/1/2: tile = (ascii + mode*$60)
EDIT_PAINT         = KVARS + $D1   ; nonzero while Paint mode (format brush) active
EDIT_CMD_PENDING   = KVARS + $D2   ; nonzero between ESC and its command key
BASIC_DEFAULT_ATTR = KVARS + $FD   ; BASIC default output attr (COLOR/FLIPX/FLIPY/ALT)
BASIC_STYLE_MASK   = KVARS + $FE   ; BASIC style override mask in overlay attr bits
STYLE_SIDE_BUF     = KVARS + $D3   ; BASIC tokenizer sidecar scratch ($03D3-$03FC)
STYLE_SIDE_BUF_SIZE = $2A
STYLE_BASE_LEN     = KVARS + $FF   ; stored-line base len ($03FF)
; Last used kernel/shared variable byte is STYLE_BASE_LEN ($03FF).

; Cursor indicator tiles: the blinking cursor previews the editor's glyph mode,
; pen, and command state (Phase 5, §4.6). The charset author draws bespoke art at
; $F8-$FF; reverse uses a glyph swap (not CHR_ALT) so the solid mode-0 square
; doesn't blank out on blink.
CUR_TILE_PENDING   = $F8           ; ESC pressed, command pending
CUR_TILE_PAINT     = $F9           ; Paint mode active
CUR_TILE_MODE0     = $FA           ; glyph mode 0/1/2 (normal): CUR_TILE_MODE0 + mode
CUR_TILE_RMODE0    = $FD           ; glyph mode 0/1/2 (reversed): CUR_TILE_RMODE0 + mode

; Default cursor glyph (mode-0 indicator: a solid square).
CURSOR_TILE        = CUR_TILE_MODE0

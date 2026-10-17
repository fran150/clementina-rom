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
; MIA: registers ($FFE0-$FFFF), status and IRQ bits, error codes, CFG field
; ids, commands, MIA-owned index ids, index flag bits (IDX_FLAG_*, bit
; numbers) and the MIA RAM layout, under MIA's own names. mia.inc is generated
; by clementina-sdk from its specs; never edit it here. Update it by copying
; the SDK's packages/runtime/asm/mia.inc (the SDK's drift check compares the
; two). See src/include/README.md.
;
; Two MIA habits the kernel relies on:
; - CFG ids $00-$0F configure the index bound to window A, $10-$1F the one
;   bound to window B. Writing a current-address byte refreshes that window's
;   data port, so a read right after repositioning returns the new byte.
; - Render control fields (MIA_VIDEO_*_OFFSET, $00020-$0003F) are reached by
;   binding MIA_VIDEO_INDEX_RENDER_CONTROL to window A and setting its address
;   (vid_seek in clementina_extra.s); the page fits in one byte of address.
; ----------------------------------------------------------------------------
.include "mia.inc"

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

; Timer 1 fires every 6250 PHI2 cycles, so it ticks at PHI2/6250: 192 Hz
; (5.2 ms) at MIA's 1.2 MHz default. The cursor toggles every 80 ticks, every
; 0.42 s at 1.2 MHz. Both follow PHI2, so KJIFFY counts CPU work (one tick per
; 6250 cycles), not wall time; programs that need wall time use MIA's timer
; (TI, TICKS). The IRQ costs 65-73 cycles per tick (73 while the cursor
; blinks), about 1% of the CPU.
VIA_T1_RELOAD       = 6250
CURSOR_BLINK_TICKS  = 80

; Kernel/system-reserved MIA index descriptors. User code must leave $F0-$FF
; alone while using kernel services. Programs own $00-$4F; MIA owns $50-$EF
; (docs/memory-map.md section 12; every id in clementina-sdk specs/mia-indexes.json).
KIDX_SCROLL_NT_SRC   = $F0
KIDX_SCROLL_NT_DST   = $F1
KIDX_SCROLL_ATTR_SRC = $F2
KIDX_SCROLL_ATTR_DST = $F3
KIDX_MEMORY_SRC      = $F4
KIDX_MEMORY_DST      = $F5

; MIA split-loads the selected font: ASCII text -> CHR bank 0 plane 0 (primary
; overlay bank), graphics/line set -> CHR bank 1 plane 0 (alternate overlay
; bank). The overlay renders plane 0; per-cell CHR_ALT selects the text bank (0)
; or the graphics bank (1). Tile code == ASCII codepoint in the text bank.
VIDEO_CHR_BANK_DEFAULT   = $00         ; text / primary bank (also bg and sprite)
VIDEO_CHR_BANK_GRAPHICS  = $01         ; alternate overlay bank: reversed glyphs (clascii)
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
; Kernel jump table - the stable ABI. The loaded image starts at $0400, the
; first byte after the kernel variables page, and the jump table is its first
; segment (clementina.cfg), so every KERN_* address below stays fixed however
; much code follows. New entries are appended at the end: existing addresses
; never move, only the code above the table slides up. Callers JSR these;
; internal routine addresses may move freely.
;
; KERN_BASE must match three other places: KERNEL's start in clementina.cfg
; (kernel.s asserts it at link time), and MIA's load and reset address in
; clementina-mia's mia.c and clementina-6502's registers.go. BASIC and WozMon
; take the base from the linker (__KERNEL_START__), so they never copy it.
;
; Anchoring the image low keeps kernel+WozMon permanently below $8000, so
; nothing resident is ever at risk from a bank switch, and BASIC's own
; resident code becomes a well-bounded, reclaimable region a loaded program
; can overwrite once it no longer needs BASIC. See docs/memory-map.md.
; ----------------------------------------------------------------------------
KERN_JUMPTAB_SIZE  = $36       ; 18 entries x 3 bytes - keep in sync with kernel.s
KERN_BASE          = $0400
KERN_COLDSTART     = KERN_BASE + $00   ; reset entry (MIA points RESET here)
KERN_WARMSTART     = KERN_BASE + $03   ; re-enter the system
KERN_CHROUT        = KERN_BASE + $06   ; A = char -> console
KERN_CHRIN         = KERN_BASE + $09   ; blocking read -> A
KERN_GETKEY_NB     = KERN_BASE + $0C   ; non-blocking; C=1 if A holds a char
KERN_CLRSCR        = KERN_BASE + $0F   ; clear screen, home cursor
KERN_PRHEX         = KERN_BASE + $12   ; A low nibble -> hex digit via CHROUT
KERN_PRBYTE        = KERN_BASE + $15   ; A -> two hex digits via CHROUT
KERN_PRSTR         = KERN_BASE + $18   ; print $00-terminated string at (KPTR)
KERN_LOAD          = KERN_BASE + $1B   ; stream a PRG file into CPU RAM (load.s)
KERN_EDITKEY       = KERN_BASE + $1E   ; screen editor: next char of edited line
KERN_CHROUT_GLYPH  = KERN_BASE + $21   ; A = tile -> console as a raw glyph (no ctrl)
KERN_WOZMON        = KERN_BASE + $24   ; enter the WOZ monitor (see src/monitor)
KERN_SET_BACKDROP  = KERN_BASE + $27   ; A = backdrop selector -> MIA_VIDEO_INDEX_BACKDROP_COLOR
KERN_IRQ           = KERN_BASE + $2A   ; kernel IRQ handler; a program's own handler
                                       ; restores A/X/Y, then JMPs here to chain
KERN_PLOT          = KERN_BASE + $2D   ; C=1: read cursor -> X=row, Y=column;
                                       ; C=0: move it to X=row, Y=column
KERN_RDTIM         = KERN_BASE + $30   ; latch MIA's clock into CLOCK_SNAPSHOT
KERN_SETTIM        = KERN_BASE + $33   ; A/X/Y (low/mid/high) -> MIA's 60 Hz clock

; ----------------------------------------------------------------------------
; MIA clock snapshot ($02F8-$02FF, top of the line-buffer page; see
; docs/memory-map.md §4). KERN_RDTIM sends MIA command $55, which latches
; MIA's clock into MIA RAM $11078-$1107F, and copies those eight bytes here.
; They stay as they are until the next KERN_RDTIM; nothing updates them in the
; background. BASIC's TI, TICKS and DELAY read the clock the same way, so they
; also refresh this copy. MIA's docs call the 60 Hz counter CLOCK_TI.
; ----------------------------------------------------------------------------
CLOCK_SNAPSHOT     = $02F8
CLOCK_MS           = CLOCK_SNAPSHOT + 0   ; 4 bytes LE: milliseconds since MIA reset, mod 2^32
CLOCK_60HZ         = CLOCK_SNAPSHOT + 4   ; 3 bytes LE: 60 Hz count, mod 5,184,000 (24 h)
CLOCK_VERSION      = CLOCK_SNAPSHOT + 7   ; 1 when MIA filled the snapshot

; ----------------------------------------------------------------------------
; Zero page map (docs/memory-map.md §2):
;   $00-$97  BASIC
;   $98-$DF  free for programs; BASIC, WozMon and the kernel never touch it
;   $E0-$E7  spare, reserved for the system
;   $E8-$EF  WozMon, while it runs
;   $F0-$FF  kernel ($FC-$FF spare)
; ----------------------------------------------------------------------------
ZP_FREE_START      = $0098   ; first zero-page byte free for programs
ZP_FREE_END        = $00DF   ; last zero-page byte free for programs

; ----------------------------------------------------------------------------
; Kernel zero page ($00F0-$00FF, see clementina.cfg KZP). Clients touch only
; what is published here; the rest is private kernel scratch.
; ----------------------------------------------------------------------------
KJIFFY             = $00F7   ; free-running 16-bit LE tick counter, +1 per VIA
                             ; Timer-1 IRQ, i.e. once per 6250 PHI2 cycles (192 Hz
                             ; at the 1.2 MHz default), so it measures CPU work,
                             ; not wall time.
                             ; Wraps silently. Stops while IRQs are masked or
                             ; Timer 1's IRQ is off. Read-only for clients. Read it
                             ; high/low/high (retry on high-byte change); the IRQ
                             ; can carry mid-read.

; ----------------------------------------------------------------------------
; Kernel variable page ($0300-$03FF). See docs/memory-map.md.
; ----------------------------------------------------------------------------
KVARS              = $0300
CURSOR_X           = KVARS + $00   ; 0..SCR_COLS-1
CURSOR_Y           = KVARS + $01   ; 0..SCR_ROWS-1
TEXT_ATTR          = KVARS + $02   ; overlay attribute/color for new cells
LAST_KEY           = KVARS + $03   ; debug: last byte returned by CHRIN
EDITOR_PEN         = KVARS + $04   ; persistent editor pen: the pen the screen
                                   ; editor reasserts into TEXT_ATTR whenever it
                                   ; takes control, so BASIC output (LIST, messages,
                                   ; styled PRINT) can drive TEXT_ATTR transiently
                                   ; without changing the color the cursor/typing use.
                                   ; (Was KEY_COUNT, a write-only debug counter.)
KLOAD_SAVED_BANK   = KVARS + $05   ; KERN_LOAD: bank mapped at entry, put back
                                   ; on return or error
DATA_BANK          = KVARS + $06   ; the bank BASIC's BANK statement picked for
                                   ; BLOAD, BRUN, BSAVE, PEEK, POKE and SYS at
                                   ; $8000-$BFFF; 0 at cold and warm start
KLOAD_RUN_BANK     = KVARS + $07   ; KERN_LOAD: the bank it was asked to load
                                   ; into, mapped again for the jump
KLOAD_MODE         = KVARS + $08   ; KERN_LOAD: bit 7 set = jump when done
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

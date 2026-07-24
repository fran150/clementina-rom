; ============================================================================
; defines_clementina.s - Clementina target for MS BASIC
; ----------------------------------------------------------------------------
; Console I/O is provided by the Clementina kernel jump table (see
; ../kernel/kernel.inc and docs/memory-map.md). The console routines live in
; clementina_extra.s; ISCNTC in clementina_iscntc.s.
;
; Several memory constants here are PROVISIONAL for a standalone BASIC build
; (compile/link check). They get retuned when BASIC is linked into the combined
; kernel image and the real end-of-code is known.
; ============================================================================

; configuration
CONFIG_2C := 1

CONFIG_NO_CR        := 1
CONFIG_SCRTCH_ORDER := 2

; zero page (BASIC owns the low/mid zero page; kernel keeps $F0-$FB)
ZP_START1 := $00
ZP_START2 := $0D
ZP_START3 := $5B
ZP_START4 := $65

; extra ZP variables
USR              := $000A

; Relocate Z14 (the PRINT output-suppress / CTRL-O flag) out of the ZP_START3
; block. That block is 11 bytes ($5B-$65), so its last byte lands on $65 - the
; exact address `.org ZP_START4` assigns to TEMPPT, the temporary-string
; descriptor stack pointer. With Z14 == TEMPPT, every `lsr Z14` (INPUT, warm
; restart) and `stx Z14` (end of program) silently mangles TEMPPT; a program
; that PRINTs string literals inside an INPUT loop then walks TEMPPT down into
; low zero page, and PUTNEW scribbles string descriptors over the GORESTART /
; GOSTROUT / USR JMP thunks at $00-$0C - crashing the interpreter (typically
; when RESTART calls the corrupted GOSTROUT). Give Z14 its own byte in the free
; span above the zero-page CHRGET routine ($C2-$DE) so it no longer aliases
; TEMPPT. zeropage.s only reserves Z14 in-block when it is not defined here.
Z14              := $00DF

; BASIC keeps its line input buffer in zero page (the proven 65C02 layout).
; WozMon uses the $0200 page; the two are never active at the same time.
; (Open item: optionally move BASIC's buffer to $0200 during full BASIC bring-up.)

; constants
STACK_TOP        := $FC
SPACE_FOR_GOSUB  := $33
WIDTH            := 40
WIDTH2           := 14
TOKEN_MON        := $FE
; Extension-token prefix. A two-byte token TOKEN_EXT + subtoken ($80|index)
; dispatches sprite/sound/etc. statements from the separate extension keyword
; table (token.s), sidestepping the 256-byte / 128-token limits of the primary
; table. $FF is free in this build (the CBM/DATAFLG uses of $FF are inactive).
TOKEN_EXT        := $FF

; ----------------------------------------------------------------------------
; Styled strings (see docs/styled-strings.md)
; ----------------------------------------------------------------------------
; Each BASIC string carries a per-character attribute byte. A string of logical
; length N occupies a 2N-byte heap block: N character bytes followed by N
; attribute bytes, so char(X) = ptr[X] and attr(X) = ptr[N+X]. The descriptor is
; unchanged (length stays the logical char count N, <= 255); the 2N allocation is
; reserved by subtracting N from FRETOP twice. STYLED_STRINGS gates the feature
; so it can be disabled for bring-up/regression against stock behavior.
STYLED_STRINGS   := 1
; Attribute applied to characters with no captured style (CHR$, STR$, numeric
; conversions, program-text literals). $00 = palette 0 (white on the blue
; backdrop), matching the kernel cold-start TEXT_ATTR. See memory-map.md §5.
DEFAULT_ATTR     := $00
; BASIC string attr-half internal bit: the character byte is an editor tile and
; must be drawn raw even if it equals a console control code such as $0D. This
; reuses the currently unexposed overlay priority bit; output masks it before
; writing TEXT_ATTR to the hardware attribute plane.
STRING_RAW_TILE  := $40
DISPLAY_ATTR_MASK := $BF
; Kernel per-cell text attribute (memory-map.md §5). STRPRT sets this before each
; character so the kernel chrout paints that character's stored attribute.
TEXT_ATTR        := $0302
BASIC_DEFAULT_ATTR := $03FD
BASIC_STYLE_MASK   := $03FE
; Kernel screen-editor dole state. While nonzero, MONRDLINE is returning bytes
; harvested from EDIT_BUF; when zero, a returned CR is the synthetic line
; terminator. BASIC's INLIN uses this to allow raw glyph bytes such as $0D in
; quoted program literals without confusing them for RETURN.
EDIT_STATE       := $0377
; Kernel buffer holding the harvested line's per-cell attributes, parallel to the
; chars BASIC's INLIN dropped into INPUTBUFFER (EDIT_ATTR_BUF[k] = attr of
; INPUTBUFFER[k]). The input-buffer->heap copy (LD399) routes these into the new
; string's attribute half. Keep in sync with EDIT_ATTR_BUF in kernel.inc.
EDIT_ATTR_BUF    := $0380
; Scratch buffer used while tokenizing a numbered BASIC line. The tokenizer
; captures string-literal attributes here, then appends the compact sidecar to
; the stored program line after its $00 terminator. This lives in currently free
; kernel variable space immediately after EDIT_CMD_PENDING ($03D2).
STYLE_SIDE_BUF      := $03D3
STYLE_SIDE_BUF_SIZE := $2A
STYLE_BASE_LEN      := $03FF
STYLE_SIDE_MAGIC0   := $CE
STYLE_SIDE_MAGIC1   := $FF

; memory layout
; BASIC program/variable workspace starts safely above the combined
; kernel+BASIC image. Keep this in sync with Makefile's MAX_KERNEL_BYTES guard:
; MIA loads the image at $0400, so RAMSTART2=$4000 allows up to $3C00 bytes of
; loaded image (kernel + BASIC + WOZ monitor). BASIC continues through Extended
; RAM bank 0 at $8000-$BFFF and uses $C000 as its exclusive memory ceiling,
; giving it a ~32,767-byte workspace after the initial empty-program marker.
; Raised from $3600 to make room for the extension-token command set (sprites,
; sound, ...); bump it further (with MAX_KERNEL_BYTES) as more commands land.
;
; AVOID TXTTAB in ~[$39FE, $3AC0]: a pre-existing latent bug (reproduces on stock
; baseline, unrelated to the extension tokens) makes INPUT misread its buffer and
; re-prompt "??" when the program text starts in that ~200-byte window. $3600 and
; $3B00+ are fine; $4000 clears it with margin. See the note in docs/memory-map.md.
RAMSTART2        := $4000

; storage: route the LOAD/SAVE tokens to the kernel jump table (stubs today).
KERN_LOAD := $041E
KERN_SAVE := $0421
SAVE:
        jmp KERN_SAVE
LOAD:
        jmp KERN_LOAD

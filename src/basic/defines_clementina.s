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

; BASIC keeps its line input buffer in zero page (the proven 65C02 layout).
; WozMon uses the $0200 page; the two are never active at the same time.
; (Open item: optionally move BASIC's buffer to $0200 during full BASIC bring-up.)

; constants
STACK_TOP        := $FC
SPACE_FOR_GOSUB  := $33
WIDTH            := 40
WIDTH2           := 14

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
; Kernel per-cell text attribute (memory-map.md §5). STRPRT sets this before each
; character so the kernel chrout paints that character's stored attribute.
TEXT_ATTR        := $0302
; Kernel buffer holding the harvested line's per-cell attributes, parallel to the
; chars BASIC's INLIN dropped into INPUTBUFFER (EDIT_ATTR_BUF[k] = attr of
; INPUTBUFFER[k]). The input-buffer->heap copy (LD399) routes these into the new
; string's attribute half. Keep in sync with EDIT_ATTR_BUF in kernel.inc.
EDIT_ATTR_BUF    := $0380

; memory layout
; BASIC program/variable workspace starts safely above the combined
; kernel+BASIC image. The RAM ceiling is $8000, where the banked Extended RAM
; window begins.
RAMSTART2        := $3000

; storage: route the LOAD/SAVE tokens to the kernel jump table (stubs today).
KERN_LOAD := $041E
KERN_SAVE := $0421
SAVE:
        jmp KERN_SAVE
LOAD:
        jmp KERN_LOAD

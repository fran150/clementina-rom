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

; PEEK's own GETADR call overwrites LINNUM; without this, a nested PEEK
; inside another statement's address argument - the extremely common
; "POKE dest, PEEK(src)" byte-copy idiom (used throughout BLOAD's own
; test suite) - silently writes back to src instead of dest, since POKE
; parses dest into LINNUM *before* evaluating the value expression, and
; the nested PEEK clobbers it without saving/restoring.
CONFIG_PEEK_SAVE_LINNUM := 1

; zero page: BASIC packs its four blocks into $00-$97, leaving $98-$DF to
; programs and $E0-$FF to the system (docs/memory-map.md §2). The asserts in
; clementina_extra.s check both ends.
ZP_START1 := $00
ZP_START2 := $0D
ZP_START3 := $13
; The ZP_START3 block is 11 bytes, Z14 (the PRINT output-suppress / CTRL-O
; flag) last. If ZP_START4 started any earlier, TEMPPT, the temporary-string
; descriptor stack pointer, would share Z14's byte: every `lsr Z14` (INPUT,
; warm restart) and `stx Z14` (end of program) would then mangle TEMPPT, and a
; program that PRINTs string literals inside an INPUT loop would walk TEMPPT
; down into low zero page, where PUTNEW scribbles string descriptors over the
; GORESTART / GOSTROUT / USR JMP thunks at $00-$0C and crashes the interpreter.
ZP_START4 := ZP_START3 + 11

; extra ZP variables
USR              := $000A

; BASIC's line input buffer lives at $0200, the page WozMon also uses for its
; line buffer (IN); the two are never active at the same time (leaving WozMon
; with Q re-enters BASIC through KERN_WARMSTART). Defining INPUTBUFFER here,
; before zeropage.s, selects msbasic's non-zero-page buffer code
; (CONFIG_NO_INPUTBUFFER_ZP / CONFIG_INPUTBUFFER_0200, defines.s), the path
; Applesoft and Commodore BASIC 2 use. Budget (docs/memory-map.md §4): up to
; INLIN_MAX typed characters at $0200-$024F, the $00 terminator at $0250, and
; the tokenizer's end-of-program $00 two bytes past it, at most $0252. The
; four bytes below the buffer, $01FC-$01FF, stage a numbered line's link and
; line number while it is copied into the program, and $01FF holds INPUT's
; leading comma; BASIC's stack stays below them (STACK_TOP).
INPUTBUFFER      := $0200
; Longest line INLIN accepts: the kernel screen editor's logical line
; (EDIT_BUF_SIZE in kernel.inc), so a harvested line is never cut short.
; EDIT_ATTR_BUF, indexed in parallel with INPUTBUFFER, holds this many bytes.
INLIN_MAX        := 80

; constants
; After STKINI the stack pointer is STACK_TOP, so pushes reach $0100+STACK_TOP
; at most. That byte is INPUTBUFFER-4, the staged link's low byte, which
; FIX_LINKS rewrites anyway; INPUTBUFFER-3..-1 must stay above the stack.
STACK_TOP        := $FC
.assert STACK_TOP <= <(INPUTBUFFER-4), error, "BASIC stack overlaps the staged line header at INPUTBUFFER-3..-1"
SPACE_FOR_GOSUB  := $33
WIDTH            := 40
WIDTH2           := 14
TOKEN_MON        := $FE
; Extension-token prefix. A two-byte token TOKEN_EXT + subtoken ($80|index)
; dispatches sprite/sound/etc. statements from the separate extension keyword
; table (token.s), sidestepping the 256-byte / 128-token limits of the primary
; table. $FF is free in this build (the CBM/DATAFLG uses of $FF are inactive).
TOKEN_EXT        := $FF

; Extension-FUNCTION-token prefix. Same idea as TOKEN_EXT but for functions
; (PLAYING(0) and friends): a two-byte token TOKEN_EXTFN + subtoken ($80|index),
; recognized in eval.s's primary-expression dispatch (mirrors UNARY), so a
; function can be added without touching the primary function table (also
; full - see PLAYING's history in token.s). $FD is free: it sits well above
; every primary token (~110 active for clementina, starting at $80) and below
; TOKEN_MON ($FE) / TOKEN_EXT ($FF).
TOKEN_EXTFN      := $FD

; Second extension-token prefix. Same idea as TOKEN_EXT, in its own two-byte
; TOKEN_EXT2 + subtoken form with its own independent 256-byte/128-token
; budget - the file-I/O and video/audio asset-family commands outgrew
; TOKEN_EXT's single table. $FC is free: the next slot down from TOKEN_EXTFN.
TOKEN_EXT2       := $FC

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
; ----------------------------------------------------------------------------
; The loaded kernel+WozMon+BASIC image sits between working RAM and the heap,
; anchored to a fixed *low* start, KERN_BASE ($0400), right after KVARS. It's
; placed there by clementina.cfg's KERNEL/BASICMEM regions (KERNEL starts at
; the fixed constant; BASICMEM starts wherever KERNEL ends, __KERNEL_LAST__)
; and loaded by an *ascending* MIA bootstrap (kernel_load_bottom_address/
; kernel_target_address in clementina-mia's mia.c and the mirrored constants
; in clementina-6502's registers.go).
;
; The kernel jump table is KERNEL's first segment (kernel.s asserts it lands
; on KERN_BASE), so BASIC takes the base from the linker's __KERNEL_START__
; instead of copying kernel.inc, which it deliberately does not .include.
; BASIC's heap fills everything above wherever the image currently ends
; (__BASICMEM_LAST__, read directly by init.s) up through $BFFF. See
; docs/memory-map.md.
.import __KERNEL_START__
KERN_BASE        := __KERNEL_START__
RAMSTART2        := KERN_BASE

; LOAD/SAVE: a BASIC program's own tokenized text to/from an SD file - see
; BASIC_LOAD/BASIC_SAVE in clementina_extra.s and docs/basic-file.md. Both are
; BASIC-resident; only BLOAD hands off to the kernel, through KERN_LOAD.
; Jump table offsets are the kernel ABI (kernel.inc) and never change.
KERN_LOAD := KERN_BASE + $1B
SAVE:
        jmp BASIC_SAVE
LOAD:
        jmp BASIC_LOAD

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

; memory layout
; PROVISIONAL: start of BASIC's program/variable workspace. In the combined
; image this becomes "just above the linked code". The RAM ceiling is $8000
; (Extended RAM bank window), so memory sizing must not pass it.
RAMSTART2        := $3000

; storage: route the LOAD/SAVE tokens to the kernel jump table (stubs today).
KERN_LOAD := $041E
KERN_SAVE := $0421
SAVE:
        jmp KERN_SAVE
LOAD:
        jmp KERN_LOAD

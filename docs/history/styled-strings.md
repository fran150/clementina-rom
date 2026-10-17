# Styled strings history

How per-character attributes in BASIC strings were designed and built. The
current reference is [../styled-strings.md](../styled-strings.md).

## Phases (2026-06)

The emulator embeds `kernel.bin` at compile time, so each phase was validated
by `make install` and an emulator rebuild.

- **Phase 0, foundations.** The design doc, plus `STYLED_STRINGS`,
  `DEFAULT_ATTR` and `TEXT_ATTR` in `defines_clementina.s`.
- **Phase 1a, the 2N size.** `GETSPA` reserves `2N` (a stack-peek double
  subtract), `MOVE_HIGHEST_STRING_TO_TOP` relocates `2N` and `FRETMP` frees
  `2N`. Validated with `FRE(0)` and a garbage-collection stress run; the
  attribute half was still unused.
- **Phase 1b, default fill.** `fill_attr_default`, hooked into `STRSPA`.
- **Phases 2 and 3, print and classify.** `STRPRT` jumps to `STRPRT_STYLED`,
  which lives in the `EXTRA` segment to get around `CODE`-segment branch
  limits, and classifies heap and literal strings by address.
- **Phase 1c, propagation.** `LEFT$`/`MID$`/`RIGHT$` (`slice_attrs`) and `CAT`
  (`cat_attrs`) carry the attribute runs, through the shared `append_attr_run`
  and `classify_heap`.
- **Phase 4, capture.** `harvest_line` reads the overlay attribute plane into
  `EDIT_ATTR_BUF`, and the input-buffer-to-heap copy (`LD399`) routes those
  bytes into the new string. Styling could now come from typing.
- **Phase 5, charset and keyboard glyph entry.** See
  [charset-keyboard.md](charset-keyboard.md).
- **Phase 6, styled program literals and BASIC style defaults.** The program
  line sidecar, and `COLOR`, `FLIPX`, `FLIPY`, `ALT` and `STYLE n` for
  `BASIC_DEFAULT_ATTR` and `BASIC_STYLE_MASK`.
- **Phase 7, independent editor and BASIC pens.** `COLOR` and its siblings
  stopped writing `TEXT_ATTR`; `STRPRT_STYLED` saves and restores the pen;
  `STROUT` prints system messages in the BASIC pen and restores the editor pen;
  `ERROR` sets the whole error line to the BASIC pen; the editor reasserts
  `EDITOR_PEN` at each line edit. Covered by `TestPenIndependence`,
  `TestUnstyledNumberUsesBasicPen`, `TestErrorMessageUsesBasicPen` and the
  `TestCursor*` tests in clementina-6502.

The first end-to-end check was
`10 POKE 770,5 : 20 INPUT A$ : 30 PRINT A$ : 40 PRINT LEFT$(A$,3):PRINT "X"+A$`:
typed `FRAN` echoed in palette 5, `LEFT$` kept the style, and `"X"+A$` showed
the literal `X` in white with `FRAN` still in palette 5.

## Choices and rejected options

- **No C64-style inline codes.** Color and reverse codes inside the string
  consume string length and break formatting.
- **Struct of arrays in one block**, not interleaved character and attribute
  pairs and not a parallel heap: aliasing and garbage collection keep working
  unchanged, and the two runs mirror MIA's two planes.
- **No 127-character cap.** Reserving `2N` by subtracting `N` twice keeps the
  stored length one byte.
- **Literals first without attributes (option A).** Program-text literals were
  left unstyled at first, then got the sidecar in Phase 6. Hiding style bytes
  inside quotes, or in the executable token stream, was rejected.
- **The attribute half stays in the same bank.** Relocating it to another
  Extended RAM bank was rejected because of the bank-switch cost inside
  garbage collection.
- **Held SHIFT and Commodore-key glyph selection** was dropped for glyph modes;
  see [charset-keyboard.md](charset-keyboard.md).

## Bugs found on the way

- `fill_attr_default` first clobbered its fill value with `tya`, giving a
  gradient of garbage attributes, and then clobbered `A`, which `STRSPA`
  returns as the byte count for the next `MOVSTR`. Input-buffer literals then
  copied 0 bytes, so direct-mode `PRINT "HELLO"` printed nothing while program
  literals worked.
- Classifying by `INDEX >= STREND` styled the startup messages with random
  bits: with `CONFIG_SCRTCH_ORDER = 2` the "BYTES FREE" message prints before
  `SCRTCH` sets `STREND`. `FRETOP` is set to `MEMSIZ` much earlier, so it
  became the boundary.
- `STRPRT` calls `FREFAC`, which frees a printed temp and raises `FRETOP` above
  it, so the temp looked like a literal. `STRPRT` now snapshots `FRETOP` into
  `DEST` before `FREFAC`.
- Routing literals and messages through the raw-glyph path stamped a blank LF
  glyph at column 0 of every message line.
- `LIST` must keep `LOWTRX` across `LINPRT`, which can clobber it through the
  string output path, before it looks for the sidecar.

## Still open

- Style-sensitive string comparison. The default is no (characters only);
  revisit if a use appears.

# Charset and keyboard history

How glyph entry from the keyboard was planned and built ("Phase 5" of the
styled-text work). The current reference is
[../phase5-charset-keyboard.md](../phase5-charset-keyboard.md).

## Sub-phases (built 2026-06-24)

- **5a, charset and banks.** `clascii.bin`, a flat 8-bank CHR dump, loads by
  size detection in the emulator's `videoLoadDefaultFont` and MIA's
  `video_load_default_font`; the older plane-0-blocks layout (`openroms.bin`,
  4096 bytes) still loads as before. The overlay alt bank was already bank 1,
  so reverse needed no kernel change. The emulator's CLI default became
  `--charset clascii`.
- **5b, glyph modes.** `EDIT_MODE`, the mode offset in `edit_echo`, `ESC M`
  and the mode cursor glyphs `$FA-$FC`.
- **5c, pen attributes.** The flip, reverse and palette bits of `TEXT_ATTR`,
  `ESC R/H/V`, `ESC 0-F`, the `ESC SPACE` reset, and the cursor's pen preview
  with the reversed glyphs `$FD-$FF`.
- **5d, Paint mode.** `ESC P`, `edit_paint_key`/`paint_stamp`, the SPACE stamp
  and the `$F9` cursor.
- **5e, 16 startup text palettes.** MIA's firmware and the emulator seed all 16
  palette banks from `clementina-text.palette.bin`. Until then the kernel
  uploaded palette RGB data itself at cold start; that code was removed.
- **5f, console ANSI decoder.** Deferred at the time, then built in MIA
  instead of the kernel on 2026-10-17 (G13): MIA's console input mode turns a
  terminal's cursor, Home, Insert and Delete sequences into the same key codes
  as the Wi-Fi path, and passes a bare ESC through after 20 ms.

The `COLOR`, `FLIPX`, `FLIPY`, `ALT` and `STYLE` statements were left out of
Phase 5 and came with the styled program literals (Phase 6, see
[styled-strings.md](styled-strings.md)).

## Choices and rejected options

- **Kernel, not the client or MIA.** The video client is one of the real input
  paths, so glyph policy there would not run for USB or console input. Putting
  charset policy in MIA would mix layers and need the same change twice (C
  firmware and Go emulator). `kernel.bin` runs identically everywhere and
  already owns the editor and the pen.
- **Modes, not held modifiers.** The first idea was C64-style SHIFT and
  Commodore-key combinations. Held modifiers corrupt the FIFO byte: Mac Option
  composes (`Option+A` gives `å`, which the client drops as non-ASCII), Cmd
  produces no text, and Ctrl makes control codes. The composed bytes are also
  scattered and host-specific, with no clean offset. Modes type plain ASCII and
  the kernel adds the offset, so the result is the same on every host.
- **FIFO only, not the held-key bitmap.** The console source has no bitmap, and
  bitmap reads add sync concerns. The ESC prefix needs only FIFO bytes.
- **256 glyphs plus reverse, not 512.** The attribute byte is full. `CHR_ALT`
  can be a ninth glyph address bit or a reverse toggle, not both.
- **No function keys for color.** They decode to nothing (a MIA table change
  would be needed), and 16 colors fit the hex digits after ESC.
- **Bespoke reversed cursor glyphs.** The mode-0 cursor is a solid square, and
  `CHR_ALT`-reversing it gives a blank cell, so the cursor would vanish on every
  blink.
- **No `TAB` fast path.** Binding `TAB` to the mode cycle was proposed and not
  built; `ESC M` is the only mode cycle.

## Bugs found on the way

- Glyph modes 1 and 2 produce bytes `CHROUT` treats as control codes (`'1'` in
  mode 1 is `$91`, cursor up; `'M'` in mode 2 is `$0D`). The fix was
  `chrout_glyph` and the `KERN_CHROUT_GLYPH` jump table entry.
- Routing BASIC's literal and message strings through the raw-glyph path
  stamped a blank LF glyph at column 0 of every message line. Literals and
  messages went back to plain `OUTDO`.
- Bank 1's reverse of the space glyph at `$80` and `$E0` (the space in glyph
  modes 1 and 2) was missing; the charset was fixed so every glyph, blanks
  included, reverses to its exact inverse. `TestClasciiReverseBankIsExactReverse`
  checks it.

## Still open

- Generating bank 1 as the inverse of bank 0 in `tools/tile-editor.html`.
- Whether Paint mode should stamp the glyph as well as the attribute (default:
  no).

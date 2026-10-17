# Charset and keyboard glyph entry

How the screen editor lets a user type any of the 256 glyphs from an ordinary
keyboard and style each one with color, flip and reverse, and how the cursor
shows all of it. It is the keyboard and charset half of the styled-text work;
[styled-strings.md](styled-strings.md) covers how the attributes travel inside
BASIC strings. How the design was chosen, and what was rejected, is in
[history/charset-keyboard.md](history/charset-keyboard.md).

Styled text is typed once, directly in the screen editor, and captured into
BASIC strings by the editor's harvest. There is no retyping to restyle and no
C64-style inline control codes.

---

## 1. Overview

A painted overlay cell is a **tile code** (nametable) plus an **attribute
byte**, and the harvest copies both into the string. This page is about what
*produces* non-default tiles and attributes from the keyboard: three glyph
modes for the tile, an ESC command layer and a Paint mode for the attribute,
and a cursor that previews the pen.

---

## 2. Hardware model

### 2.1 Overlay cell = tile + attribute

A console/overlay cell is two parallel bytes:

- **Nametable tile code** `0–255` — *which glyph*. Written by `chrout` straight
  from the character byte (MIA RAM `$10080`, [memory-map.md §12](memory-map.md)).
- **Attribute byte** — *how it looks* (`$10468`).

The glyph's identity is the tile code; everything else is the attribute. The
two planes are independent, which is why restyling without retyping is natural.

### 2.2 Attribute byte layout

The same layout as every background cell
([clementina-sdk `docs/architecture/video.md`](https://github.com/fran150/clementina-sdk/blob/main/docs/architecture/video.md)):

| bits 0–3 | bit 4 | bit 5 | bit 6 | bit 7 |
| --- | --- | --- | --- | --- |
| **palette** (16) | **flip-X** (L/R) | **flip-Y** (U/D) | priority | **CHR_ALT** (reverse) |

- **Palette (bits 0–3).** Overlay text is 1bpp with a transparent paper: pixel
  value 0 is not drawn (the backdrop shows through) and pixel value 1 is
  **color 1 of the selected palette bank**. For text, the palette field picks
  one of 16 ink colors (§2.4).
- **flip-X / flip-Y (bits 4/5).** The renderer mirrors the glyph horizontally
  or vertically.
- **priority (bit 6).** Not exposed by the editor. BASIC uses it inside string
  storage as the raw-tile tag and masks it out before writing `TEXT_ATTR`
  ([styled-strings.md §3.5](styled-strings.md#35-literals-and-the-style-sidecar)).
- **CHR_ALT (bit 7) = reverse.** The overlay reads the glyph from its alternate
  CHR bank instead of its primary one.

### 2.3 Charset = 256 glyphs in two banks

Clementina uses **256 distinct glyphs**:

- **bank 0, plane 0**: the 256 glyphs, normal.
- **bank 1, plane 0**: the **same 256 glyphs, reversed** (ink and paper
  swapped) at the same tile positions.

`video_init` points the overlay's primary bank at 0 and its alternate bank at 1
and decodes both as 1bpp on plane 0, so `CHR_ALT` (the pen's reverse bit)
swaps between them and reverse is free per cell. Bank 1 is the exact reverse of
bank 0 for all 256 glyphs, blanks included (a blank reverses to a solid block),
so every glyph reverses in every glyph mode.

The shipped charset is `clascii.bin`, a flat dump of the whole CHR region
(8 banks × 6144 bytes = 49,152 bytes), as `tools/tile-editor.html` exports
"CHR — all 8 banks". MIA's firmware (`charsets/clascii.bin`, the CMake
`MIA_CHARSET` option) and the emulator (`assets/computer/mia/charsets/clascii.bin`,
`--charset clascii`, the default) load it when video starts. A file whose
length is a multiple of 6144 is copied flat into CHR memory; anything else
loads as 2048-byte plane-0 blocks, one bank each (the older `openroms.bin`).
The editor exports `clascii.chr-all.bin`; rename it `clascii.bin`.

> **The ASCII glyphs must sit at tile positions `$20–$7E`** in bank 0, because
> the console and BASIC write a character's ASCII byte directly as its tile
> code (`chrout`). Normal text only renders if tile `$41` is `A`, and so on.

### 2.4 Startup text palettes

The editor's `ESC 0–F` and BASIC's `COLOR n` pick one of the 16 palette banks.
For overlay text each bank's **color 1** is the ink; **color 0** is the
backdrop blue in every bank, although overlay pixel 0 is transparent anyway.
The shipped palette, `clementina-text.palette.bin`:

| key | palette | text ink |
| --- | --- | --- |
| `0` | 0 | white (the default) |
| `1` | 1 | red |
| `2` | 2 | orange |
| `3` | 3 | yellow |
| `4` | 4 | green |
| `5` | 5 | cyan |
| `6` | 6 | backdrop blue: invisible on the default backdrop, and `BCOLOR 6` restores it |
| `7` | 7 | violet |
| `8` | 8 | magenta / pink |
| `9` | 9 | black |
| `A` | 10 | gray |
| `B` | 11 | light gray |
| `C` | 12 | dark red / brown |
| `D` | 13 | dark green |
| `E` | 14 | blue |
| `F` | 15 | white, the same as palette 0 |

Palettes 1-5 and 7-8 run red, orange, yellow, green, cyan, violet, magenta,
with the backdrop blue at 6 between them; 9-F are neutral and utility colors.

The palette is 256 bytes, 16 banks of 8 RGB565 little-endian colors, in the
format `tools/tile-editor.html` imports and exports:

- Firmware: `clementina-mia/palettes/clementina-text.palette.bin`, selected by
  the CMake `MIA_PALETTE` option and copied into palette RAM at video start.
- Emulator: `clementina-6502/assets/computer/mia/palettes/clementina-text.palette.bin`,
  selected by `--palette clementina-text`.

The kernel carries no RGB data; it only writes and harvests the 4-bit palette
number in each cell attribute. To change the colors, edit the `.palette.bin`
in the tile editor and rebuild the firmware and emulator assets.

---

## 3. Input model

### 3.1 Three sources, one byte stream

Input comes from one of three mutually exclusive sources: the **Wi-Fi client**,
**USB host** and the **console**. USB host is reserved for a USB keyboard on a
later board; rev 1 is powered through the Pico's USB port, so MIA reports that
mode unavailable. Whatever the source, the kernel reads one thing, the **text
FIFO**:

- `INPUT_STATUS` `$FFF2` — bit 0 `TEXT_READY` ($01), bit 1 `KEYBOARD_DOWN` ($02).
- `INPUT_CHAR` `$FFF3` — read-to-pop the next byte ($00 when empty).
- `INPUT_CHAR_COUNT` `$FFF4`.

The kernel's `getkey_nb` and `chrin` (`src/kernel/input.s`) drain it.

### 3.2 Key codes

Printable ASCII arrives as text. The editing keys (Enter `$0D`, Tab `$09`,
Backspace `$08`, Esc `$1B`, Home `$13`, Insert `$94`, Delete `$7F`, cursor
right/left/down/up `$1D`/`$9D`/`$11`/`$91`) arrive as the same bytes from every
source. The full table, with which side produces each code, is clementina-mia's
[`docs/input.md`, Key Codes](https://github.com/fran150/clementina-mia/blob/main/docs/input.md#key-codes).
Function keys produce nothing.

### 3.3 What each source sends

- **Wi-Fi client**: printable ASCII (`$20–$7E`, from the host's layout) as text,
  plus HID key events that MIA decodes into the editing codes. The client
  drops non-ASCII text, such as Mac `Option+A` giving `å`. The high glyph codes
  (`$80–$FF`) come from the kernel's glyph modes (§4.2), not from the input
  layer.
- **USB host** (later board): raw HID reports through the same decode.
- **Console**: raw bytes from the serial terminal. MIA's console input mode
  turns the terminal's cursor, Home, Insert and Delete sequences into the same
  codes, and passes a bare Esc through after 20 ms with no further byte, so
  the ESC commands below work there too.

### 3.4 The held-key bitmap

MIA also keeps a 32-byte bitmap of currently held keys (MIA RAM `$11000`). The
editor doesn't use it: the console has none, and the design needs no held
modifiers.

---

## 4. Editor design

Everything here is kernel-side and FIFO-only, so it works the same on every
input source with no client or firmware change.

### 4.1 Two separate modes

- **Glyph mode** `0/1/2` — *which tile* a typed key produces (§4.2).
- **Paint mode** — a non-typing editor state where SPACE stamps the pen (§4.5).

### 4.2 Glyph selection — 3 glyph modes, single add

A typed printable byte `c` (`$20–$7E`) becomes a tile:

```
tile = (c + mode * $60) & $FF      ; mode in {0,1,2} -> offset $00 / $60 / $C0
```

- **Mode 0 = identity** (`$20–$7E`), so normal text renders (§2.3).
- **Mode 1** → `$80–$DE`. **Mode 2** → `$E0–$FF`, then wraps to `$00–$3E`.
- Control bytes (CR, arrows and so on) bypass the offset; only printables
  `$20–$7E` are offset.

Coverage: the keyboard delivers 95 codes (`$20–$7E`; `$7F` is never sent as
text), so each mode misses its 96th slot, but the modes overlap and only two
tiles are unreachable. **254 of 256 tiles are typeable**; the holes are **`$7F`
and `$DF`**, the images of the missing `$7F` input in modes 0 and 1. Put blanks
there in the charset. `$20–$3E` is reachable two ways (mode 0 and mode 2's
wrap), which is what covers mode 2's missing `$3F` slot.

### 4.3 Pen = the attribute byte

The pen is the kernel's `TEXT_ATTR` (`$0302`), which `chrout` paints into the
attribute plane, saved in `EDITOR_PEN` (`$0304`) so it survives BASIC output:

- bits 0–3 = palette / color (0–15)
- bit 4 = flip-H, bit 5 = flip-V, bit 7 = reverse (CHR_ALT)
- bit 6 (priority) stays 0

Because `chrout` writes `TEXT_ATTR` to the attribute plane, flip, reverse and
color take effect as soon as the bits are set, and the harvest captures them
into strings. The pen and glyph mode persist for the session; only `ESC SPACE`
and cold start reset them, much like the C64's current color.

### 4.4 ESC-prefix command layer

`ESC` (`$1B`) is a one-shot command prefix: press ESC, and the next key is a
command.

| Keys | Action |
| --- | --- |
| `ESC` `M` | Cycle glyph mode `0 → 1 → 2 → 0` |
| `ESC` `R` | Toggle reverse (CHR_ALT, bit 7) |
| `ESC` `H` | Toggle flip-horizontal (bit 4) |
| `ESC` `V` | Toggle flip-vertical (bit 5) |
| `ESC` `0` … `ESC` `9` | Set color / palette **0–9** |
| `ESC` `A` … `ESC` `F` | Set color / palette **10–15** |
| `ESC` `P` | Enter **Paint mode** (§4.5) |
| `ESC` `SPACE` | Reset the pen and glyph mode (palette 0, no flip or reverse, mode 0) |
| `ESC` `<any other>` | Cancel the prefix (no-op) |

Rules:

- **The key is the palette number** (`ESC 5` → palette 5, `ESC F` → palette 15),
  matching the 4-bit field. The colors are the startup palette's (§2.4).
- **No collisions:** `0–9`/`A–F` are colors; the commands `M/R/H/V/P` are all
  above `F`.
- **Case-insensitive** (`ESC h` is `ESC H`). The FIFO sends lowercase unless
  Shift is held, so the parser folds case.

### 4.5 Paint mode (format brush)

For restyling existing text without retyping (for example, making a whole
string red and flipped).

- **Enter:** `ESC P`. **Exit:** `ESC`.
- While in Paint mode:
  - **arrows** move the cursor (no typing).
  - **SPACE** overwrites the **entire** attribute byte of the cell under the
    cursor with the current pen, then advances right (wrapping to the next row,
    like typing).
  - all other keys are ignored.
- The stamp replaces color, flip and reverse at once, whatever the cell had.
  Restyle cells, press RETURN, and the harvest captures the new attributes into
  the string.

### 4.6 Cursor = live pen preview (8 glyphs, `$F8–$FF`)

The blinking cursor shows the editor state with 8 indicator tiles:

| tile | cursor shows |
| --- | --- |
| `$F8` | ESC pressed — command pending (neutral) |
| `$F9` | Paint mode active |
| `$FA` / `$FB` / `$FC` | glyph mode 0 / 1 / 2 (normal) |
| `$FD` / `$FE` / `$FF` | glyph mode 0 / 1 / 2 **reversed** (R0/R1/R2) |

Display rules:

- **Reverse is shown by glyph swap** (`$FA–$FC` ↔ `$FD–$FF`), not by setting
  CHR_ALT on the cursor cell: the mode-0 cursor is a solid square, and a
  reversed solid square is blank, so the cursor would vanish on every blink.
- **Flip and color are shown through the cursor cell's attribute**, which is
  the pen with CHR_ALT cleared. The renderer transforms the indicator live, so
  the cursor previews the pen. (Flip doesn't show on the symmetric mode-0
  square; it does on the others.)
- The Paint cursor (`$F9`) previews the pen, so you see what SPACE will stamp;
  the ESC-pending cursor (`$F8`) is neutral.
- The blink alternates between the real cell content and the indicator, on the
  Timer 1 tick ([memory-map.md §10](memory-map.md)).

---

## 5. Reserved tile map (charset author must honor)

| tiles | use |
| --- | --- |
| `$20–$7E` | ASCII glyphs (mode-0 identity; required for normal text) |
| `$00–$1F`, `$80–$FF` | graphics glyphs (reached via modes 1/2) |
| `$F8–$FF` | cursor indicator art (also *typeable* in mode 2 — dual-use) |
| `$7F`, `$DF` | unreachable by typing — leave blank/throwaway |
| bank 1 (all) | CHR_ALT / reverse set: the exact reverse of every bank 0 glyph |

`$F8–$FF` are reachable in mode 2 (`ascii $38–$3F` → `$F8–$FF`), so typing
those in mode 2 paints the cursor art. Either accept the dual use or place
sensible dual-purpose glyphs there.

---

## 6. Kernel implementation

Editor state (the end of the `KVARS` page; see [kernel.inc](../src/kernel/kernel.inc)):

- `EDIT_MODE` (`$03D0`) — current glyph mode (0/1/2).
- `EDIT_PAINT` (`$03D1`) — nonzero while Paint mode is active.
- `EDIT_CMD_PENDING` (`$03D2`) — nonzero between ESC and the command key (drives
  the `$F8` cursor).
- The pen: `TEXT_ATTR` (`$0302`), kept in `EDITOR_PEN` (`$0304`).
- All of them are zeroed in `coldstart`.

The code, in [editor.s](../src/kernel/editor.s) and
[console.s](../src/kernel/console.s):

1. **`edit_line` dispatch.** After `chrin`: if `EDIT_PAINT` → `edit_paint_key`; else
   `$1B` (ESC) → `edit_command`; else CR/BS/DEL/INSERT; else `edit_echo`.
2. **`edit_echo`.** Printable `$20–$7E` gets the mode offset
   (`tile = (c + EDIT_MODE*$60) & $FF`) then draws via **`chrout_glyph`** (raw tile,
   no control interpretation); true control codes (arrows/HOME) go to `chrout`.
3. **`edit_command`.** Sets pending, reads the command key, case-folds, dispatches:
   `M` cycle mode; `R/H/V` toggle reverse/flip-H/flip-V; `0–9`/`A–F` set palette via
   `set_palette`; `SPACE` reset (`EDIT_MODE=0`, `TEXT_ATTR=EDITOR_PEN=0`); `P` enter
   Paint; else no-op. Each pen change is also stored in `EDITOR_PEN`.
4. **`edit_paint_key` / `paint_stamp`.** Arrows → `chrout` (move); SPACE writes
   `TEXT_ATTR` to the overlay attribute cell then advances via `chrout` cursor-right;
   ESC exits.
5. **`cursor_indicator_tile` + `cursor_show`** (console): the cursor tile is chosen
   from `(EDIT_CMD_PENDING, EDIT_PAINT, EDIT_MODE, reverse-bit)` per §4.6, and the
   cursor cell attribute = `TEXT_ATTR & $7F` (CHR_ALT cleared so the solid square
   never blanks).

### 6.1 Glyphs that look like control codes

`chrout` treats several bytes as control codes: `$0D` (CR), `$11/$13/$1D` and
`$91/$9D` (cursor moves), and so on. Glyph modes 1 and 2 produce exactly these
codes (`'1'` in mode 1 is `$91`; `'M'` in mode 2 is `$0D`), so plain `chrout`
would move the cursor instead of drawing the glyph. **`chrout_glyph`**, behind
the jump table entry **`KERN_CHROUT_GLYPH`** (`$0421`), draws `A` as a raw tile
with the normal advance, wrap, scroll and line link, and never interprets it.
`chrout`'s printable path and `chrout_glyph` share `put_glyph_raw`.

BASIC's PRINT has the same hazard for **heap** strings, which can carry graphic
tiles. `STRPRT_STYLED` ([clementina_extra.s](../src/basic/clementina_extra.s))
splits:

- **literals and messages** print through plain `OUTDO`: they carry CR/LF
  formatting `chrout` must interpret, and the LF (`$0A`) must be ignored.
- **heap strings** go through `styled_outc`: an untagged `$0D` stays a newline
  (`OUTDO` + `PRINTNULLS`, so `CHR$(13)` still works); plain text `$20–$7E`
  keeps going through `OUTDO` (so `Z14`/`POSX` bookkeeping is unchanged);
  editor-harvested control-range tiles are tagged in the string's attribute
  half and draw raw via `MONCOUT_GLYPH → KERN_CHROUT_GLYPH`, advancing `POSX`
  one column and honoring `Z14`.

Limit: tile `$00` cannot be stored inside a BASIC program literal, because
`$00` ends a tokenized line. The other mode-2 control-range tiles, `$0D`
included, survive in stored literals.

`chrout` and `chrout_glyph` accept tile codes `$80–$FF`, and the editor consumes
ESC (`$1B`) before it can reach `chrout`.

---

## 7. Charset, firmware and client

- **Charset asset.** `clascii.bin`: bank 0 = the 256 glyphs, ASCII at
  `$20–$7E`, cursor art at `$F8–$FF`; bank 1 = the exact reverse of bank 0.
  `$7F` and `$DF` can't be typed (§4.2), so leave them blank. Author it in
  `tools/tile-editor.html`, export "CHR — all 8 banks", and name the file
  `clascii.bin`. The emulator test `TestClasciiReverseBankIsExactReverse`
  checks the bank 1 rule.
- **Kernel configuration.** The overlay alt bank is bank 1 (`video_init`), so
  `CHR_ALT` renders bank 1.
- **No client or firmware support needed** for the command scheme: ESC and
  ASCII flow through the existing paths. The held-key bitmap and function keys
  are not used.
- **Palettes.** MIA's firmware and the emulator seed all 16 banks (§2.4). The
  ROM only stores palette numbers in `TEXT_ATTR` and cell attributes.

The BASIC statements `COLOR`, `FLIPX`, `FLIPY`, `ALT` and `STYLE n` set BASIC's
own default attribute and override policy; they are in
[styled-strings.md §3.6](styled-strings.md#36-present-print).

---

## 8. Tests

`go test ./pkg/computers/clementina/ -run TestPhase5` in clementina-6502 drives
the real kernel through the input FIFO and covers the mode cycle and offset,
`$91` staying a glyph, ESC colors, `ESC R/H/V` and reset, Paint enter and exit,
Paint stamp then harvest, styled attribute harvest, a BASIC `PRINT` round trip
of high and control-range tiles, and `READ` skipping styled sidecars. The
charset loader has `TestVideoLoadFontFlatFullChrDump` in the `mia` package.

To test a ROM change: `make` builds `build/kernel.bin`, `make install` copies
it into the emulator (and `make install-firmware` into MIA's tree), then
rebuild the emulator (`go run`) to embed it. `tests/run_input.py` runs the
emulator's tests against this checkout's ROM without installing it.

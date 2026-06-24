# Phase 5 — charset + keyboard glyph entry

Status: **partly implemented and emulator-validated** (2026-06-24). Sub-phases
5a–5e are done; 5f (console ANSI decoder) remains optional/deferred. See §8 for
the per-sub-phase status and the Go tests that cover it.

This document is the authoritative record of the Phase 5 design *and* its
implementation: how the user types/styles the full 256-glyph character set from an
ordinary keyboard, how the editor exposes color / flip / reverse, and how the
cursor reflects all of it. It is the keyboard+charset counterpart to
[styled-strings.md](styled-strings.md) (which covers how per-character attributes
live inside BASIC strings). Read both before touching Phase 5.

All addresses/line references were verified during the 2026-06-24 session; re-check
them before relying on them — the code moves.

---

## 1. Goal

Let the user, from a normal US keyboard, (a) type any of 256 glyphs, and (b) style
each glyph with color, horizontal/vertical flip, and reverse — directly in the
screen editor, so styled/graphic text is typed once and captured into BASIC strings
by the existing styled-strings harvest. No retyping to restyle; no C64-style inline
control codes.

This builds on the styled-strings capture (Phases 0–4 + 1c, done): a painted cell is
a **tile code** (nametable) plus an **attribute byte**, and the harvest already
copies both into the string. Phase 5 is what *produces* non-default tiles and
attributes from the keyboard.

---

## 2. Hardware model (verified)

### 2.1 Overlay cell = tile + attribute

A console/overlay cell is two parallel bytes:

- **Nametable tile code** `0–255` — *which glyph*. Written by `chrout` straight from
  the character byte. (`$10080`, see styled-strings/memory-map.)
- **Attribute byte** — *how it looks*. (`$10468`.)

The glyph's *identity* is the tile code; everything else is the attribute. The two
are independent planes (this is why "restyle without retyping" is natural).

### 2.2 Attribute byte layout

From the renderer
([clementina-video-client `internal/render/renderer.go:49-52`](../../go/clementina-video-client/internal/render/renderer.go#L49-L52),
applied at `renderer.go:240-269`):

| bits 0–3 | bit 4 | bit 5 | bit 6 | bit 7 |
| --- | --- | --- | --- | --- |
| **palette** (16) | **flip-X** (L/R) | **flip-Y** (U/D) | priority | **CHR_ALT** (reverse) |

- **Palette (bits 0–3).** Overlay text is **1bpp with a transparent paper**: pixel
  value 0 is skipped (the blue backdrop shows through), pixel value 1 is drawn as
  **color 1 of the selected palette** (`renderer.go:253-256`). So for text the
  palette field behaves as "pick 1 of 16 ink colors." The attribute format already
  addresses palette banks `0–15`; Phase 5e loads all 16 banks at startup.
- **flip-X / flip-Y (bits 4/5).** The renderer mirrors the glyph
  (`chrPixel`, `renderer.go:264-269`: `x=7-x` / `y=7-y`). flip-X = horizontal,
  flip-Y = vertical.
- **priority (bit 6).** Overlay-vs-background layering. **Not exposed** to the editor.
- **CHR_ALT (bit 7) = reverse.** When set, the overlay reads the glyph from a second
  CHR bank (`renderer.go:246-249`: normal `regOverlayChrBank`, alt `regOverlayAltChr`).

### 2.3 Charset = 256 glyphs in two banks

A charset image split-loads into CHR banks (256 glyphs / 2048-byte plane each,
[`pkg/components/mia/video.go:754-766`](../../go/clementina-6502/pkg/components/mia/video.go#L754-L766)).
Clementina uses **256 distinct glyphs**, laid out as:

- **bank 0 plane 0** — the 256 glyphs, normal.
- **bank 1 plane 0** — the **same 256 glyphs, reversed** (ink/paper swapped) at the
  *same* tile positions.

`CHR_ALT` flips between them, so **reverse is free per cell** and there are 256
*distinct* glyphs (not 512). The user supplies this charset image. The kernel
already points the overlay-alt bank at bank 1 (`video.s` `video_init`,
`VIDEO_CHR_BANK_GRAPHICS`), so `CHR_ALT` (the pen's reverse bit) renders bank 1 —
**no kernel change was needed for reverse.** Whatever art sits in bank 1 is what a
reversed cell shows; if a bank-1 slot is blank, reversing that glyph shows blank.

**Charset format and loading (5a, done).** The shipped charset is
`assets/computer/mia/charsets/clascii.bin`, a **flat dump of the whole CHR region**
(8 banks × 6144 B = 49152 B), exactly as `tools/tile-editor.html` exports "CHR —
all 8 banks". The emulator's `videoLoadDefaultFont`
([`pkg/components/mia/video.go`](../../go/clementina-6502/pkg/components/mia/video.go))
now detects this: a file whose length is a nonzero multiple of a full 6144-B bank
is copied **flat** into CHR memory (every plane of every bank); the older
plane-0-blocks layout (e.g. `openroms.bin`, 4096 B) still split-loads as before.
The Clementina CLI now defaults to `--charset clascii`
([`cmd/clementina.go`](../../go/clementina-6502/cmd/clementina.go)); the cursor
indicator art at `$F8–$FF` (§4.6) assumes clascii. Note the editor exports
`clascii.chr-all.bin`; the asset must be named `clascii.bin` for `--charset clascii`
to resolve.

> Important constraint: **the ASCII glyphs must sit at tile positions `$20–$7E`** in
> bank 0, because the console and BASIC write a character's ASCII byte *directly* as
> its tile code (`chrout`). Normal text only renders if tile `$41` is `A`, etc.

### 2.4 Startup text palettes (5e, done)

The editor already accepts `ESC 0–F`, and the attribute byte already stores a
4-bit palette index. 5e makes those 16 values real by loading palette banks
`$90–$9F` at cold start.

For overlay 1bpp text, each palette bank should keep **color 0** as the backdrop
blue for consistency, even though overlay pixel 0 is transparent and lets the
global backdrop show through. **Color 1** is the visible text ink.

Startup text-ink order:

| key | palette | text ink |
| --- | --- | --- |
| `0` | 0 | white / default |
| `1` | 1 | red |
| `2` | 2 | orange |
| `3` | 3 | yellow |
| `4` | 4 | green |
| `5` | 5 | cyan |
| `6` | 6 | blue |
| `7` | 7 | violet / purple |
| `8` | 8 | magenta / pink |
| `9` | 9 | black |
| `A` | 10 | gray |
| `B` | 11 | light gray |
| `C` | 12 | dark red / brown |
| `D` | 13 | dark green |
| `E` | 14 | backdrop blue |
| `F` | 15 | bright white / highlight |

This deliberately keeps `0` as the existing white/default, puts the rainbow-ish
run at `1–8` (`red → orange → yellow → green → cyan → blue → violet → magenta`),
and leaves `9–F` for neutral/utility colors. The exact RGB565 values live in
the MIA/emulator default palette asset, using the exact 256-byte palette format
exported by `tools/tile-editor.html` (`16 banks × 8 RGB565 little-endian colors`).
Current asset locations:

- Firmware: `clementina-mia/palettes/clementina-text.palette.bin`, selected by the
  CMake `MIA_PALETTE` option and copied into MIA palette RAM by video startup.
- Emulator: `clementina-6502/assets/computer/mia/palettes/clementina-text.palette.bin`,
  selected by `--palette clementina-text` and copied into emulated MIA palette RAM
  by `videoLoadDefaultPalette`.

The kernel does **not** carry RGB565 palette data; it only writes/harvests the
4-bit palette number in each cell attribute. Palette maintenance should happen by
importing/editing/exporting the `.palette.bin` in the tile editor and rebuilding
the firmware/emulator asset. The table above is the stable user-facing mapping.

---

## 3. Input model (verified)

### 3.1 Three sources, one byte stream

Input arrives from one of three **mutually exclusive** sources (only one owns input
at a time): **WiFi client**, **USB host**, **Console**. Regardless of source, the
kernel reads one unified thing — the **text FIFO**:

- `INPUT_STATUS` `$FFF2` — bit 0 `TEXT_READY` ($01), bit 1 `KEYBOARD_DOWN` ($02).
- `INPUT_CHAR` `$FFF3` — read-to-pop the next byte ($00 when empty).
- `INPUT_CHAR_COUNT` `$FFF4`.

The kernel's `getkey_nb`/`chrin` ([src/kernel/input.s:38-47](../src/kernel/input.s#L38-L47))
already drain this FIFO.

### 3.2 The MIA owns the keyboard decode (C64-KERNAL style)

Non-printable editing keys are decoded **in the MIA** (not the client), so every
source produces the same bytes
([`pkg/components/mia/input.go:646-681`](../../go/clementina-6502/pkg/components/mia/input.go#L646-L681)):

| key | byte | key | byte |
| --- | --- | --- | --- |
| Enter | `$0D` | Home | `$13` |
| Tab | `$09` | Insert | `$94` |
| Backspace | `$08` | Delete-fwd | `$7F` |
| Escape | `$1B` | Right/Left | `$1D` / `$9D` |
| | | Down/Up | `$11` / `$91` |

**Function keys decode to nothing today** (not in the table). Printable ASCII reaches
the FIFO as text (so it must *not* decode here, or it would double-enqueue).

### 3.3 What each source sends

| source | sends | mapped to | bitmap? |
| --- | --- | --- | --- |
| **WiFi client** | printable ASCII (`$20–$7E`, host layout) + HID key events | text → FIFO; HID → 32-byte bitmap + `inputDecodeKeyUsage` → FIFO (`input_wifi.go:348`) | yes |
| **USB host** | raw USB HID reports | same bitmap + decode (printable→ASCII needs a usage→ASCII table — minimal/WIP) | yes |
| **Console** | raw bytes (serial/dev) | injected straight into FIFO, text-only, no decode (`input.go:831-840`) | **no** |

The WiFi client filters its *text* channel to printable `$20–$7E`
([`forwarder.go:340-344`](../../go/clementina-video-client/internal/input/forwarder.go#L340-L344));
non-ASCII/composed keys (e.g. Mac Option+A → `å`) are dropped and ride the HID path
instead. This is deliberate: the host gives *Unicode*, only ASCII maps cleanly, and
the **high glyph codes (`$80–$FF`) are synthesized by the kernel** (§4.2), not the
input layer.

### 3.4 The 32-byte held-key bitmap (available, not used by Phase 5)

A 256-bit / 32-byte bitmap at MIA `$11000` (1 bit per HID usage) reports
**currently-held** keys; index `$61` streams all 32 bytes, probes `$50–$57` read one
byte, status bit `KEYBOARD_DOWN` gates it, and modifier keys (HID `$E0–$E7`) live in
byte `$1C`. **Phase 5 does not use it** (console has none, and our design is
modifier-free) — but it's the path if we ever want held-modifier input.

---

## 4. Chosen design

Everything below is **kernel-side and FIFO-only**, so it works identically across
WiFi / USB-host / console with no client or firmware change.

### 4.1 Two orthogonal "modes" — keep them distinct

- **Glyph mode** `0/1/2` — affects *which tile a typed key produces* (§4.2).
- **Paint mode** — a non-typing editor state where SPACE stamps the pen (§4.5).

### 4.2 Glyph selection — 3 glyph modes, single add

A typed printable byte `c` (`$20–$7E`) becomes a tile:

```
tile = (c + mode * $60) & $FF      ; mode in {0,1,2} -> offset $00 / $60 / $C0
```

- **Mode 0 = identity** (`$20–$7E`), required so normal text renders (§2.3).
- **Mode 1** → `$80–$DE`. **Mode 2** → `$E0–$FF` then wraps to `$00–$3E`.
- Control bytes (CR, arrows, etc.) bypass the offset — only printables `$20–$7E` are
  offset.

Coverage: the keyboard delivers 95 codes (`$20–$7E`; `$7F`/DEL is never sent as
text), so each mode loses its 96th slot — but the modes overlap, so only **two**
tiles end up unreachable. **254 of 256 tiles are typeable**; the holes are
**`$7F` and `$DF`** (put blanks/throwaways there in the charset). They are the
images of the missing `$7F` input: mode 0 maps `$7F→$7F`, mode 1 maps `$7F→$DF`,
and no other mode covers them. `$20–$3E` is reachable two ways (mode 0 and mode
2's wrap), which is exactly what rescues mode 2's otherwise-missing `$3F` slot.

### 4.3 Pen = the attribute byte (reuse `TEXT_ATTR`)

The "pen" is exactly the kernel's `TEXT_ATTR` (`$0302`) that `chrout` already paints
into the attribute plane. Phase 5 just starts using all its bits:

- bits 0–3 = palette / color (0–15)
- bit 4 = flip-H, bit 5 = flip-V, bit 7 = reverse (CHR_ALT)
- bit 6 (priority) stays 0

Because `chrout` already writes `TEXT_ATTR` to the attribute plane, **flip/reverse/
color "just work"** once those bits are set, and the harvest already captures them
into strings. No new pen variable is needed.

### 4.4 ESC-prefix command layer

`ESC` (`$1B`) is a one-shot command prefix: press ESC, the next key is a command.
All bytes flow through the FIFO on every source, so no decode changes are needed.

| Keys | Action |
| --- | --- |
| `ESC` `M` | Cycle glyph mode `0 → 1 → 2 → 0` |
| `ESC` `R` | Toggle reverse (CHR_ALT, bit 7) |
| `ESC` `H` | Toggle flip-horizontal (bit 4) |
| `ESC` `V` | Toggle flip-vertical (bit 5) |
| `ESC` `0` … `ESC` `9` | Set color / palette **0–9** |
| `ESC` `A` … `ESC` `F` | Set color / palette **10–15** |
| `ESC` `P` | Enter **Paint mode** (§4.5) |
| `ESC` `SPACE` | Reset pen + glyph mode to default (palette 0, no flip/reverse, mode 0) |
| `ESC` `<any other>` | Cancel the prefix (no-op) |

Rules:
- **Color indexing is 0-based: key value = palette number** (`ESC 5` → palette 5,
  `ESC F` → palette 15). Matches the 4-bit palette field exactly.
- **Color names come from the startup palette table** (§2.4). `ESC 6` means
  "palette 6"; after 5e that palette is blue by convention.
- **No collisions:** `0–9`/`A–F` are colors; commands are `M/R/H/V/P` (all above
  `F`).
- **Case-insensitive** (`ESC h` == `ESC H`; `ESC a` == `ESC A`). The FIFO sends
  lowercase unless Shift is held, so the parser folds case.
- **Optional fast path:** bind plain **`TAB` (`$09`) → cycle glyph mode** — single
  keystroke, all sources, no MIA change. Confirm `TAB` is otherwise unused in the
  line editor first. (`ESC M` stays available regardless.)

### 4.5 Paint mode (format brush)

For restyling existing text without retyping (e.g. "make this whole string red and
flipped").

- **Enter:** `ESC P`. **Exit:** `ESC`.
- While in Paint mode:
  - **arrows** — move the cursor (no typing).
  - **SPACE** — overwrite the **entire** attribute byte of the cell under the cursor
    with the current pen, then advance right (wrap to the next row, like typing).
  - all other keys ignored.
- Stamps the full attribute byte (color + flip + reverse at once), replacing whatever
  the cell had. Composes with the harvest: restyle cells, press RETURN, and the new
  attributes are captured into the string.

### 4.6 Cursor = live pen preview (8 glyphs, `$F8–$FF`)

The blinking cursor reflects the full editor state. Reserve **8 indicator tiles**:

| tile | cursor shows |
| --- | --- |
| `$F8` | ESC pressed — command pending (neutral) |
| `$F9` | Paint mode active |
| `$FA` / `$FB` / `$FC` | glyph mode 0 / 1 / 2 (normal) |
| `$FD` / `$FE` / `$FF` | glyph mode 0 / 1 / 2 **reversed** (R0/R1/R2) |

Display rules:
- **Reverse is shown by glyph swap** (`$FA–$FC` ↔ `$FD–$FF`), **not** by setting
  CHR_ALT on the cursor cell. Reason: the mode-0 cursor is a **solid square**, and
  CHR_ALT-reversing a solid square yields a blank cell → the cursor would vanish on
  every blink. Bespoke R0/R1/R2 art avoids that. (`$F8`/`$F9` are non-square, so they
  *may* use CHR_ALT for reverse if desired.)
- **Flip + color are shown via the cursor cell's attribute** (flip-X/Y + palette);
  CHR_ALT stays 0 on the cursor cell. The renderer transforms the indicator live, so
  the cursor previews the pen. (Flip is invisible on the symmetric mode-0 square —
  accepted; it shows on the 1/2 and R indicators.)
- The Paint cursor (`$F9`) previews the pen (so you see what SPACE will stamp); the
  ESC-pending cursor (`$F8`) is neutral.
- Blink still alternates between the real cell content and the indicator (existing
  Timer 1 machinery).

---

## 5. Reserved tile map (charset author must honor)

| tiles | use |
| --- | --- |
| `$20–$7E` | ASCII glyphs (mode-0 identity; required for normal text) |
| `$00–$1F`, `$80–$FF` | graphics glyphs (reached via modes 1/2) |
| `$F8–$FF` | cursor indicator art (also *typeable* in mode 2 — dual-use) |
| `$7F`, `$DF` | unreachable by typing — leave blank/throwaway |
| bank 1 (all) | CHR_ALT / reverse set (ideally reversed copies of bank 0; in the shipped clascii it is an independent set) |

Note `$F8–$FF` are reachable in mode 2 (`ascii $38–$3F` → `$F8–$FF`), so typing those
in mode 2 paints the cursor art. Either accept the dual use or place sensible
dual-purpose glyphs there.

---

## 6. Kernel implementation surface (as built)

Editor state (KVARS tail; see [kernel.inc](../src/kernel/kernel.inc)):

- `EDIT_MODE` (`$03D0`) — current glyph mode (0/1/2).
- `EDIT_PAINT` (`$03D1`) — nonzero while Paint mode is active.
- `EDIT_CMD_PENDING` (`$03D2`) — nonzero between ESC and the command key (drives
  the `$F8` cursor).
- Pen = existing `TEXT_ATTR` (`$0302`). No new variable.
- All three are zeroed in `coldstart`.

What was built (all in [editor.s](../src/kernel/editor.s) and
[console.s](../src/kernel/console.s)):

1. **`edit_line` dispatch.** After `chrin`: if `EDIT_PAINT` → `edit_paint_key`; else
   `$1B` (ESC) → `edit_command`; else CR/BS/DEL/INSERT as before; else `edit_echo`.
2. **`edit_echo`.** Printable `$20–$7E` gets the mode offset
   (`tile = (c + EDIT_MODE*$60) & $FF`) then draws via **`chrout_glyph`** (raw tile,
   no control interpretation); true control codes (arrows/HOME) go to `chrout`.
3. **`edit_command`.** Sets pending, reads the command key, case-folds, dispatches:
   `M` cycle mode; `R/H/V` toggle reverse/flip-H/flip-V; `0–9`/`A–F` set palette via
   `set_palette`; `SPACE` reset (`EDIT_MODE=0`, `TEXT_ATTR=0`); `P` enter Paint; else
   no-op.
4. **`edit_paint_key` / `paint_stamp`.** Arrows → `chrout` (move); SPACE writes
   `TEXT_ATTR` to the overlay attribute cell then advances via `chrout` cursor-right;
   ESC exits.
5. **`cursor_indicator_tile` + `cursor_show`** (console): the cursor tile is chosen
   from `(EDIT_CMD_PENDING, EDIT_PAINT, EDIT_MODE, reverse-bit)` per §4.6, and the
   cursor cell attribute = `TEXT_ATTR & $7F` (CHR_ALT cleared so the solid square
   never blanks).

### 6.1 The chrout control-code collision (the §10 open question, resolved)

`chrout` **does** treat several high/low bytes as control codes — `$0D` (CR),
`$11/$13/$1D` and the high `$91/$9D` (cursor moves), etc. Glyph modes 1/2 produce
exactly these codes (e.g. `'1'` in mode 1 → `$91`; `'M'` in mode 2 → `$0D`), so
routing them through plain `chrout` would move the cursor instead of drawing the
glyph. Fix: a new console entry **`chrout_glyph`** (and ABI slot
**`KERN_CHROUT_GLYPH = $0427`**) draws `A` as a raw tile with the normal advance /
wrap / scroll / line-link, never interpreting it as control. `chrout`'s printable
path and `chrout_glyph` share `put_glyph_raw`.

The BASIC PRINT path has the same hazard, but only for **heap** strings (which can
carry graphic tiles). `STRPRT_STYLED`
([clementina_extra.s](../src/basic/clementina_extra.s)) splits:

- **literals/messages** print through plain `OUTDO` (unchanged from before Phase 5)
  — they carry CR/LF formatting `chrout` must interpret, and the LF (`$0A`) must be
  ignored. (Routing them raw stamped a blank LF glyph at column 0 of every message
  line — a regression caught in testing and fixed.)
- **heap strings** go through `styled_outc`: untagged `$0D` stays a newline
  (`OUTDO` + `PRINTNULLS`, so `CHR$(13)` remains compatible); plain text
  `$20–$7E` keeps going through `OUTDO` (so `Z14`/`POSX` bookkeeping is
  unchanged); editor-harvested control-range tiles are tagged in the BASIC string
  attr half and draw raw via `MONCOUT_GLYPH → KERN_CHROUT_GLYPH`, advancing
  `POSX` one column and honoring `Z14`.

Known limitation: tile `$00` cannot be represented directly inside stored BASIC
source literals because `$00` terminates a tokenized line. Other mode-2
control-range tiles, including `$0D`, round-trip through stored literals.

Verified during implementation:
- `chrout`/`chrout_glyph` accept tile codes `$80–$FF`; ESC (`$1B`) is consumed by
  the editor before it can reach `chrout`.
- `regOverlayAltChr` (overlay-alt bank) already points at bank 1 — reverse works
  with no kernel change.
- Pen + glyph mode persist within a session (only `ESC SPACE` / cold start reset
  them), matching the C64 "color persists across lines" feel.
- `TAB` fast-path was **not** added (ESC M is the only mode cycle); revisit if
  wanted.

---

## 7. MIA / charset / client side

- **Charset assets** — `clascii.bin` is a flat 8-bank CHR dump (bank 0 = the 256
  glyphs, ASCII at `$20–$7E`, cursor art at `$F8–$FF`; bank 1 = the CHR_ALT/reverse
  set). Typing leaves `$7F` and `$DF` unreachable (§4.2) — leave them blank. Author
  via `tools/tile-editor.html`, export "CHR — all 8 banks", and name the asset
  `clascii.bin`.
- **Kernel config** — already done: the overlay-alt bank = bank 1 (`video_init`), so
  CHR_ALT renders bank 1 with no change.
- **No client/firmware change required** for the command scheme (ESC + ASCII all flow
  through existing paths). The 32-byte bitmap and function-key decode are *not* used.
- **Palette expansion (5e)** — done in MIA firmware + emulator, not the ROM. Both
  seed all 16 palette banks from the editor-exported
  `clementina-text.palette.bin` at video startup. Keep color 0 as the backdrop blue
  in every bank and set color 1 to the ink color listed in §2.4. The ROM only
  stores palette indexes in `TEXT_ATTR`/cell attributes.
- **Optional later — console ANSI decoder:** so a terminal's arrow keys
  (`ESC [ A`, …) fold into the nav codes (`$91`, …) on the console source. It must
  pass a *bare* `ESC` (not followed by `[`) through so the ESC-prefix still works on
  console.

---

## 8. Execution plan (sub-phases) — status

- **5a — charset + banks. DONE.** `clascii.bin` (flat 8-bank dump) loads via the
  format detection in `videoLoadDefaultFont`; overlay-alt bank already = bank 1;
  Clementina defaults to `--charset clascii`.
- **5b — glyph modes. DONE.** `EDIT_MODE`, the mode offset in `edit_echo`, `ESC M`,
  mode cursor indicators `$FA–$FC`. (No `TAB` fast-path.)
- **5c — pen attributes. DONE.** flip/reverse/palette bits of `TEXT_ATTR`;
  `ESC R/H/V`, `ESC 0–F`, `ESC SPACE` reset; cursor previews the pen + R-glyph swap
  `$FD–$FF`.
- **5d — Paint mode. DONE.** `ESC P`, `edit_paint_key`/`paint_stamp`, SPACE stamp +
  advance, `$F9` cursor.
- **5e — 16 startup text palettes. DONE.** MIA firmware and the emulator seed all
  16 palette banks (`$90–$9F`) from `clementina-text.palette.bin`, an editor-
  exported 256-byte palette file. The tile editor can import/export this raw
  palette format so the startup colors can be maintained visually; the ROM no
  longer uploads palette RGB data itself.
- **5f — console ANSI decoder. DEFERRED (optional).** Terminal arrows over the
  console source still don't fold into nav codes; not needed for WiFi/USB-host.

Out of scope for Phase 5e but now implemented in Phase 6: BASIC language commands
`COLOR`, `FLIPX`, `FLIPY`, `ALT`, and `STYLE n`. These live with the styled-literal
/ BASIC runtime work, because they change how BASIC chooses default attributes and
how it applies sidecar attributes during `PRINT`/`LIST`. See
[styled-strings.md §3.5–3.6](styled-strings.md#35-literals--initial-decision-option-a)
for the sidecar, `BASIC_DEFAULT_ATTR`, and `STYLE n` bitmask policy.

Tests (`go test ./pkg/computers/clementina/ -run TestPhase5`) drive the real kernel
through the input FIFO and cover: mode cycle + offset, the `$91`-stays-a-glyph
regression, ESC colors, ESC R/H/V + reset, Paint enter/exit, Paint stamp→harvest,
styled attribute harvest, a BASIC `PRINT` round-trip of high/control-range tile
strings, and `READ` skipping styled sidecars. The
charset loader has `TestVideoLoadFontFlatFullChrDump` in the `mia` package.

Build/verify mirrors styled-strings: `make` builds `build/kernel.bin`,
`make install`, then rebuild the emulator (`go run`) to re-embed it.

---

## 9. Rationale / rejected alternatives

- **Why kernel-side, not the client or MIA firmware?** The video-client is one of the
  *real* input paths (WiFi), not just the emulator, so glyph policy there wouldn't run
  under USB-host/console. The MIA is a generic peripheral; baking Clementina charset
  policy into it is wrong layering and doubles maintenance (C firmware + Go emulator).
  `kernel.bin` is the one artifact that runs identically everywhere and already owns
  the editor and pen state. So: **decode/glyph policy = kernel**.
- **Why modes, not held modifiers (Option/Alt/CBM)?** Held modifiers corrupt the FIFO
  byte: Mac Option composes (`Option+A → å`, dropped as non-ASCII); Cmd produces no
  text; Ctrl makes control codes. And the composed bytes are a scattered, host-
  specific set — no clean `+offset`. Modes type plain ASCII (clean on every source)
  and the **kernel** adds the offset → deterministic, layout-independent, contiguous.
- **Why FIFO-only, not the 32-byte bitmap?** Console has no bitmap, and bitmap reads
  add sync concerns. The ESC-prefix needs only FIFO bytes, so it works on all three
  sources uniformly.
- **Why 256 glyphs + reverse, not 512 distinct?** The attribute byte is full (4
  palette + flip-X + flip-Y + priority + CHR_ALT). CHR_ALT can be *either* a 9th glyph
  address bit (→512 distinct, no reverse) *or* a reverse toggle (→256 + reverse) — not
  both. We chose 256 + reverse.
- **Why not function keys for color?** They decode to nothing today (would need a MIA
  table change), and 16 direct colors fit the hex digits under ESC anyway.
- **Why keep bespoke R0/R1/R2 cursor glyphs?** The mode-0 cursor is a solid square;
  CHR_ALT-reversing it is blank, so the reversed cursor would disappear on blink.

---

## 10. Open questions

- **Resolved — chrout vs high tiles.** `chrout` *does* interpret `$0D/$11/$13/$1D/
  $91/$9D` as control; Phase 5 added `chrout_glyph`/`KERN_CHROUT_GLYPH` and routed
  the editor echo and `STRPRT_STYLED` through it (§6.1).
- **Resolved — persistence.** Pen + glyph mode persist within a session; reset only
  via `ESC SPACE` / cold start.
- **Open — bank 1 content.** The shipped `clascii.bin` does **not** carry strict
  reversed copies of bank 0 (e.g. bank-1 `'A'` is blank); it's an independently
  authored alternate set. So `ESC R` shows whatever art is in bank 1, which may be
  blank for some glyphs. If full reverse coverage is wanted, fill bank 1 with the
  inverted bank-0 glyphs in `tools/tile-editor.html`.
- **Open — tile editor reverse-bank authoring.** Convenience for generating bank 1
  as the inverse of bank 0 is not yet in the editor.
- **Open — Paint stamping the glyph too** (currently attribute-only). Default no.
- **Implemented in Phase 6 — BASIC style/default commands.** Programmatic
  commands `COLOR`, `FLIPX`, `FLIPY`, `ALT`, and `STYLE n` live with the styled
  program-literal work so the default attribute, sidecar attributes, and override
  policy are designed together (see
  [styled-strings.md §3.5–3.6](styled-strings.md#35-literals--initial-decision-option-a)).
- **Deferred — `TAB` mode fast-path** and the **console ANSI decoder** (5f).

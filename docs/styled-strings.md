# Styled strings — per-character attributes in BASIC strings

Clementina BASIC strings carry a display attribute for every character
(palette, flip X/Y and alternate bank) that travels **with** the string, so a
program can type and print styled text without C64-style inline color or
reverse codes. This page is the reference for how that works. How it was built,
phase by phase, is in [history/styled-strings.md](history/styled-strings.md).

---

## 1. What a styled string is

The MIA overlay stores the screen as two parallel planes: a **nametable** (one
tile/glyph byte per cell, at `$10080`) and an **attribute** plane (one
attribute byte per cell, at `$10468`). The attribute byte holds the palette,
flip-X, flip-Y, priority and alternate-bank bits
([memory-map.md §12](memory-map.md)).

A character's attribute is remembered as part of the BASIC string. When the
user types `A` (flipped, blue, reversed) into a string and later `PRINT`s it,
it renders exactly as typed. The attribute is stored alongside the character,
not encoded as escape codes that consume string length and break formatting.

---

## 2. MS BASIC string storage

The design builds on how msbasic stores strings ([src/basic/string.s](../src/basic/string.s),
[print.s](../src/basic/print.s), [zeropage.s](../src/basic/zeropage.s)):

- **A string is a 3-byte descriptor** `[length, ptr_lo, ptr_hi]`. `length` is a
  single byte, so **255 characters at most**. Descriptors live in the variable
  table, arrays and the temp-descriptor stack (`TEMPST`).
- **Characters are contiguous bytes**, in one of two homes:
  - **In program text**, for string literals. `STRLT2` points the descriptor
    straight into the tokenized program and copies only volatile sources (the
    input buffer). `A$="HELLO"` uses no string heap.
  - **In the string heap**, growing down from `FRETOP` toward `STREND`, for
    anything built at runtime. `GARBAG` compacts it.
- **Every routine treats 1 byte as 1 character**: `MOVSTR1` copies byte by
  byte, `LEN` returns the length byte, `CAT` adds lengths,
  `LEFT$`/`MID$`/`RIGHT$` index by byte offset, `CHR$` makes a 1-byte string
  and `ASC` reads one byte.
- **PRINT** (`STRPRT`) calls `OUTDO → MONCOUT` (the kernel's `CHROUT`) once per
  byte, and `CHROUT` writes the tile and the current `TEXT_ATTR` (`$0302`).

Zero-page anchors (zeropage.s): `STREND`, `FRETOP`, `FRESPC`, `MEMSIZ`,
`INDEX`, `DSCPTR`, `TEMPST`. Heap strings occupy `[FRETOP .. MEMSIZ)`.

---

## 3. The design

### 3.1 Layout — struct-of-arrays inside one allocation

A string of logical length `N` occupies a **single `2N`-byte block**: `N`
character bytes followed by `N` attribute bytes.

```text
descriptor [N, ptr]:
        offset:  0      1     ...  N-1   N    N+1  ...  2N-1
        ptr[i]:  c0     c1    ...  c(N-1) a0   a1   ...  a(N-1)
                 └──────── chars ───────┘ └──────── attrs ────────┘

        char(X) = ptr[X]
        attr(X) = ptr[N + X]
```

The descriptor is **unchanged**: `length` still holds the **logical char count**
`N` (≤ 255). So these are untouched: `LEN`, string comparison (it compares only
the first `N` bytes, so it ignores style), `ASC`, `VAL`, the 255 limit, and the
descriptor/variable/array storage format.

Why one block of two runs:

- **Aliasing just works.** `A$ = B$` copies the 3-byte descriptor; both point at
  the same block, so both see the same attrs. No deep copy.
- **GC stays one contiguous move.** `GARBAG` relocates a string as a single run;
  the only change is the span is `2N` instead of `N`.
- **Matches the hardware.** Chars and attrs are each contiguous, mirroring the
  MIA's two separate planes.

The cost: slicing and concatenation must find the **source's** attribute run at
`source_ptr + source_len`. For a substring that is the **parent's** length,
which the call site already has in `DSCPTR` (§3.4).

### 3.2 Allocation — reserve `2N` without a 16-bit length

`GETSPA` computes `FRETOP - A`, and the subtraction is already 16-bit (it
borrows into `FRETOP+1`); only the amount `A` is 8-bit. To reserve `2N` it
subtracts `N` **twice**, `(FRETOP - N) - N`, which works for `N` up to 255
(510 bytes). So:

- The stored length stays a **single byte** (`N`, ≤ 255), and full 255-character
  styled strings work.
- Every other place that moves or frees a string does the same "`N` twice" with
  the existing 16-bit pointer math: `FRETMP` (free: add `N` twice), and
  `GARBAG` / `MOVE_HIGHEST_STRING_TO_TOP` (span end = `LOWTR + N + N`, moved by
  the 16-bit `BLTU2`).

Styled strings cost twice the heap of plain ones, inside BASIC's free
workspace ([memory-map.md §8](memory-map.md)).

### 3.3 Default attribute & minted strings

`DEFAULT_ATTR = $00` (palette 0, white on blue, the cold-start `TEXT_ATTR`,
memory-map §5). Strings minted without style — `CHR$`, `STR$`, numeric to
string and so on — fill their attribute half with `DEFAULT_ATTR`.

The fill happens once, in `STRSPA` (the single allocation chokepoint), through
`fill_attr_default`. `STRSPA`/`GETSPA` return `A = N`, and the literal-copy
path (`STRLT2`/`LD399`) uses that `A` as the byte count for the next `MOVSTR`,
so `fill_attr_default` **must preserve `A`**.

### 3.4 Slicing & concatenation

`LEFT$/MID$/RIGHT$` **copy** into a fresh allocation (`STRSPA` + `MOVSTR1`);
they don't alias into the parent. `slice_attrs` adds a **second copy pass** for
the attribute run, after the character copy:

- The slice's attr **source** = `parent_ptr + parentLen + start` = `INDEX +
  parentLen`. `parentLen` is still readable at `(DSCPTR),0` (FRETMP doesn't
  touch `DSCPTR`).
- The slice's attr **destination**: after the char `MOVSTR1`, `FRESPC` has
  auto-advanced by `count`, so it is already at the result's attr region.

`CAT` (`cat_attrs`): the result's attribute region starts at the new total
length, and each source's attrs are found through that source's own length.
Both use `append_attr_run`, which copies the run for a heap source and steps
`FRESPC` over it (keeping the default fill) for a program-text literal.
`classify_heap` decides which, while the source is still live (§5).

### 3.5 Literals and the style sidecar

String literals in stored program lines keep their typed attributes in a
Clementina-only **style sidecar**, appended to the stored line after its `$00`
terminator, so the tokenized line itself is unchanged. A literal with no
sidecar record has no attribute half and prints at the BASIC pen (§3.6). The
layout:

```text
[next lo][next hi][line lo][line hi][tokenized text...][$00]
[$CE][$FF][sidecar_len][record_count]
[literal_offset][literal_len][attr0][attr1]...[attrN-1]
...
```

`literal_offset` is the offset of the first literal character within the
tokenized line text (not the opening quote), `literal_len` is the character
count, and the following bytes are raw overlay attribute bytes. The tokenizer
records every non-empty quoted literal while entering a numbered line; lines
with no quoted literals have no sidecar. `$CE,$FF` is the marker: `$FF` can't
be a next-line pointer's high byte in Clementina's base-RAM program area, so a
plain line is never misread as a sidecar. The tokenizer builds the records in
`STYLE_SIDE_BUF` (`$03D3`, 42 bytes, memory-map §5) before appending them. If
a line's records don't fit there (a 4-byte header plus 2 bytes and one byte
per character for each literal), the whole line is stored unstyled.

When `STRLIT`/`STRLT2` evaluates a program-text literal, it looks for a sidecar
record covering it (`styled_program_literal_to_heap`). With none, the
descriptor points straight into program text as usual. With one, it allocates a
styled heap string, copies the literal into the character half and the sidecar
attrs into the attribute half, and returns that temp. From there `PRINT`,
assignment, `CAT` and the slices work unchanged.

BASIC's line input keeps the bytes the screen editor harvests. `KERN_EDITKEY`
does the interactive editing and then doles raw overlay tile bytes from
`EDIT_BUF`; `INLIN` stores them verbatim, using `EDIT_STATE` only to tell a
harvested `$0D` tile from the final RETURN. That is how glyph-mode tiles such
as `$A1`, `$91`, `$0D` or `$02` survive inside quoted program literals.

Editor-harvested bytes outside printable ASCII (`<$20` or `>=$7F`) get
`STRING_RAW_TILE` (`$40`) ORed into their string or sidecar attribute byte.
That bit is internal to BASIC's string storage and reuses the overlay priority
bit, which the editor never sets. `styled_outc` checks it to draw
control-range tiles raw (including tile `$0D`) and masks it out before writing
`TEXT_ATTR`, so it never reaches the overlay as priority. Minted strings
(`CHR$`, `STR$`, numeric strings) keep `DEFAULT_ATTR`, so `CHR$(13)` still
prints a newline.

Code that walks from one program line to the next skips the sidecar:
`FIX_LINKS`, sequential execution, `LIST` (which follows the next-line links
and never prints sidecar bytes) and the `DATA`/`READ` scan
(`style_skip_sidecar_at_index_y`). `LIST` shows quoted literals in their stored
attrs, so listing a program and re-entering the lines keeps their style through
the screen harvest, and it treats high bytes inside quotes as glyphs, not
tokens.

### 3.6 Present (PRINT)

`STRPRT` (print.s) jumps to `STRPRT_STYLED`, which walks the characters. For a
heap (styled) string it combines each character's stored attribute with the
BASIC default and policy, writes the result to the kernel's `TEXT_ATTR`
(`$0302`) and outputs the character. Unstyled output — numbers, unstyled
literals, messages — has no attribute half and prints at the **BASIC pen**.
Literals written in a color are promoted to heap strings with their attrs (a
direct-mode literal through `STRLT2`/`EDIT_ATTR_BUF`, a program literal through
its sidecar) and print in their written colors. So `PRINT "FRAN";A` prints
`FRAN` in its stored color and the number `A` in the BASIC pen.

The **editor pen and the BASIC pen are independent**; BASIC output never
changes the pen the user set with ESC:

- **Editor pen / current pen** — the kernel's `TEXT_ATTR` (`$0302`), kept in
  `EDITOR_PEN` (`$0304`). The keyboard sets it (ESC commands); it colors the
  cursor, new typed or stamped cells, and so the literals typed with it.
  `STRPRT_STYLED` saves it at entry and restores it at every exit, and the
  editor puts `EDITOR_PEN` back into `TEXT_ATTR` at each line edit, so its
  color survives `LIST`, errors and styled `PRINT`.
- **BASIC default attribute / BASIC pen** — `BASIC_DEFAULT_ATTR` (`$03FD`), set
  by `COLOR`/`FLIPX`/`FLIPY`/`ALT`. It colors (a) system messages — startup,
  error and `READY.` text and `INPUT` prompts, which `STROUT` prints by loading
  the BASIC pen into `TEXT_ATTR` and restoring the editor pen after (`ERROR`
  sets the whole error line to it) — (b) unstyled `PRINT` output such as
  numbers and unstyled literals, and (c) the override source for styled
  strings through the mask. `COLOR` does not change the color of typed text;
  that is the editor pen.
- **Style policy mask** — `BASIC_STYLE_MASK` (`$03FE`). Effective output attr:

```text
effective = (stored_attr & ~override_mask) | (BASIC_DEFAULT_ATTR & override_mask)
```

`BASIC_STYLE_MASK = $00` means AUTO: use the stored sidecar or heap attrs.
`BASIC_STYLE_MASK = $BF` overrides palette, flip-X, flip-Y and CHR_ALT from
`BASIC_DEFAULT_ATTR` and leaves the internal raw-tile bit 6 alone.

User-facing commands:

- `COLOR n` — set default palette color, `0-15`.
- `FLIPX n` — set default flip-X off/on (`0` off, nonzero on).
- `FLIPY n` — set default flip-Y off/on.
- `ALT n` — set default CHR_ALT/reverse off/on.
- `STYLE n` — set override policy as a bitmask: bit 0/color, bit 1/flip-X,
  bit 2/flip-Y, bit 3/ALT. Bits set use `BASIC_DEFAULT_ATTR`; bits clear use the
  string's stored attr. Examples: `STYLE 0` = AUTO, `STYLE 1` = override color
  only, `STYLE 1 OR 8` = override color and ALT, `STYLE 15` = override all.
  Values outside `0-15` raise `ILLEGAL QUANTITY`.

Screen commands (out-of-range values raise `ILLEGAL QUANTITY`):

- `CLS` — clear the screen, home the cursor and reset BASIC's column counter
  to 0.
- `CRSR col,row` — move the cursor to column `0-39`, row `0-24` (`0,0` is the
  top-left corner) and set BASIC's column counter to match.
- `BCOLOR n` — set the screen backdrop to the ink color of palette bank
  `0-15`, the same color `COLOR n` gives text; `BCOLOR 6` restores the default
  blue.

Output depends on whether the string is a **heap** string (it has an attribute
half and can hold graphic tile codes) or a program-text **literal or message**
(no attribute half, plain text):

- **Literals and messages → plain `OUTDO`.** They contain CR/LF formatting that
  `chrout` must interpret: message strings begin with CR+LF, and the LF (`$0A`)
  must be *ignored*.
- **Heap strings → `styled_outc`.** Graphic tile codes `$80–$FF` (and mode-2
  wraps into `$00–$3E`) collide with `chrout`'s control codes (`$0D` CR,
  `$11/$13/$1D/$91/$9D` cursor moves). Plain text `$20-$7E` goes through `OUTDO`
  (keeping the `Z14`/`POSX` bookkeeping). An untagged `$0D` stays a newline
  (`OUTDO` + `PRINTNULLS`, so `CHR$(13)` still breaks lines). Tagged
  control-range bytes and all other non-plain bytes are drawn as **raw tiles**
  via `MONCOUT_GLYPH → KERN_CHROUT_GLYPH` (`$0421`), advancing `POSX` one column
  and honoring `Z14`.

See [phase5-charset-keyboard.md §6.1](phase5-charset-keyboard.md). One storage
limit remains: tile `$00` can't be stored inside BASIC program text, because
`$00` ends a tokenized line.

### 3.7 Capture (INPUT / screen editor)

1. **Harvest** — `harvest_line` (editor.s) reads the overlay nametable into
   `EDIT_BUF` through index `$B8`, and the matching **attribute plane** cells
   into the parallel `EDIT_ATTR_BUF` (`$0380`, 80 bytes). Same start cell, same
   count.
2. **Alignment** — BASIC's `INLIN` stores the doled characters at
   `INPUTBUFFER,x` from `x = 0` (inline.s), and the editor doles `EDIT_BUF`
   from index 0, so `EDIT_ATTR_BUF[k]` is the attribute of `INPUTBUFFER[k]`.
   `INLIN` stores the already-edited bytes raw, high bytes and control-range
   tiles included, instead of filtering to printable ASCII.
3. **Route into the string** — the input-buffer-to-heap literal copy
   (`STRLT2`/`LD399`, taken when the literal lives in the input buffer's page,
   `$02xx`) copies, after the character `MOVSTR`, `N` attribute bytes from
   `EDIT_ATTR_BUF + (STRNG1 − INPUTBUFFER)` into the new string's attribute
   half (`FRESPC`, already at `base + N`). This replaces the `DEFAULT_ATTR`
   fill for input-buffer strings only; minted strings keep the default fill.

Typed cells get the editor pen, which the keyboard sets (`ESC 0–F` color,
`ESC R/H/V` reverse and flip, `ESC P` Paint mode — see
[phase5-charset-keyboard.md](phase5-charset-keyboard.md)). A program can also
set it with `POKE 770,n` (770 = `$0302` = `TEXT_ATTR`). `READ`/`DATA` values
come from program text and get `DEFAULT_ATTR`.

Example: `10 POKE 770,5` / `20 INPUT A$` / `30 PRINT A$`, RUN, type some text,
and it prints back in palette 5. The `?` prompt is drawn through `OUTDO`, which
doesn't reset `TEXT_ATTR`, so the pen survives into the editor.

### 3.8 Charset

The default 1bpp charset uses two banks: bank 0 holds the glyphs and bank 1
the same glyphs reversed at the same positions, so "reverse" is the `CHR_ALT`
attribute bit. Glyph selection, the ESC commands, Paint mode, the cursor
indicators and the charset tile map are in
[phase5-charset-keyboard.md](phase5-charset-keyboard.md). The charset is
authored in `tools/tile-editor.html`.

---

## 4. Where the code is

| File | Styled-string work |
| --- | --- |
| `src/basic/string.s` | `2N` allocation (`GETSPA`, `STRSPA`, `fill_attr_default`), free and garbage collection of `2N` spans, the attribute copies of `CAT`/`LEFT$`/`MID$`/`RIGHT$` (`cat_attrs`, `slice_attrs`, `append_attr_run`, `classify_heap`), input-buffer capture from `EDIT_ATTR_BUF`, program-literal promotion (`styled_program_literal_to_heap`) |
| `src/basic/print.s` | `STRPRT` jumps to `STRPRT_STYLED` |
| `src/basic/clementina_extra.s` | `STRPRT_STYLED`, `styled_outc`, `MONCOUT_GLYPH`, `COLOR`/`FLIPX`/`FLIPY`/`ALT`/`STYLE` |
| `src/basic/program.s` | Sidecars: appending them to stored lines, skipping them between lines, `LIST` |
| `src/basic/inline.s` | `INLIN` keeps raw harvested bytes, using `EDIT_STATE` |
| `src/basic/defines_clementina.s` | `STYLED_STRINGS`, `DEFAULT_ATTR`, `STRING_RAW_TILE`, the buffer addresses |
| `src/kernel/editor.s` | `harvest_line` fills `EDIT_ATTR_BUF` |

`STYLED_STRINGS` gates the whole feature, so it can be turned off to compare
with stock behavior.

---

## 5. Heap or literal: the `FRETOP` test

`PRINT`, slicing and `CAT` must know whether a string has an attribute half.
`STRPRT_STYLED` calls a string a heap string when its data pointer is
`>= FRETOP`; anything below is program text or the input buffer.

- `STREND` can't be the boundary: with `CONFIG_SCRTCH_ORDER = 2`, the cold-start
  "BYTES FREE" message prints *before* `SCRTCH` sets `STREND`
  ([init.s](../src/basic/init.s)). `FRETOP` is set to `MEMSIZ` much earlier,
  so it is always valid.
- **Classify before the free.** `STRPRT` calls `FREFAC`, which frees a printed
  temp and raises `FRETOP` above it. A freed temp keeps its bytes, attribute
  half included, so `STRPRT` snapshots `FRETOP` into `DEST` *before* `FREFAC`,
  and `STRPRT_STYLED` classifies against that snapshot. Slicing and `CAT` follow
  the same rule: `classify_heap` runs while the source is still live, against
  the live `FRETOP`.

String comparison ignores style: it compares characters only.

---

## 6. Tests

clementina-6502 covers styled strings in `pkg/computers/clementina`, among them
`TestPhase5StyledHarvestCapturesAttribute`, `TestPenIndependence`,
`TestUnstyledNumberUsesBasicPen`, `TestErrorMessageUsesBasicPen` and the
`TestCursor*` tests. To test a ROM change, `make` builds `build/kernel.bin`,
`make install` copies it into the emulator, and the emulator must be rebuilt
(`go run`) to embed it; `tests/run_input.py` does the same without installing.

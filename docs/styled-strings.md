# Styled strings — per-character attributes in BASIC strings

Status: **styled strings working through Phase 6 program-literal sidecars —
emulator-validated** (2026-06-24). Phases 0–5 and the initial Phase 6 sidecar,
`LIST`, `$0D` raw-glyph, and `DATA`/`READ` paths are implemented; BASIC
default/style-policy commands remain future work.
Validated with
`10 POKE 770,5 : 20 INPUT A$ : 30 PRINT A$ : 40 PRINT LEFT$(A$,3):PRINT "X"+A$`:
typed `FRAN` echoed in palette 5, `LEFT$` kept the style, and `"X"+A$` rendered
the literal `X` white (DEFAULT_ATTR) with `FRAN` still palette 5 — confirming
capture, slice/concat propagation, and heap-vs-literal classification.

This document is the authoritative record of the design discussion for giving
Clementina BASIC strings *per-character display attributes* (palette, flip X/Y,
priority, alternate bank) that travel **with** the string, so a program can
type/print styled text without C64-style inline color/reverse control codes. It
exists so the design survives a lost session — read it before resuming work.

---

## 1. Goal

The MIA overlay stores the screen as two parallel planes: a **nametable** (one
tile/glyph byte per cell, at `$10080`) and an **attribute** plane (one attribute
byte per cell, at `$10468`). The attribute byte selects palette (bits 0-3
today), and is intended to also carry flip-X, flip-Y, priority, and
alternate-bank. See [memory-map §12](memory-map.md).

We want a character's attribute to be remembered as part of a BASIC string. When
the user types `A` (flipped, blue, reversed) into a string and later `PRINT`s
it, it should render exactly as typed — the attribute is stored alongside the
character, not encoded as inline escape/color codes that consume string length
and break formatting (the C64 approach we are deliberately *not* using).

---

## 2. How MS BASIC stores strings today (investigation result)

Confirmed by reading [src/basic/string.s](../src/basic/string.s),
[print.s](../src/basic/print.s), [zeropage.s](../src/basic/zeropage.s):

- **A string is a 3-byte descriptor** `[length, ptr_lo, ptr_hi]`. `length` is a
  single byte → **255 chars max**. Descriptors live in the variable table,
  arrays, and the temp-descriptor stack (`TEMPST`, `PUTNEW` at string.s:110).
- **Characters are contiguous bytes**, in one of two homes:
  - **In program text**, for string *literals*. `STRLT2` does **not** copy a
    literal to the heap — it points the descriptor straight into the tokenized
    program (string.s:88-96). Only volatile sources (the input buffer) are
    copied. Consequence: `A$="HELLO"` consumes **zero** string heap.
  - **In the string heap**, growing **down** from `FRETOP` toward `STREND`, for
    anything built at runtime. `GARBAG` compacts it (string.s:185).
- **Every routine assumes 1 byte = 1 character**: `MOVSTR1` copies byte-by-byte
  (string.s:458), `LEN` returns the length byte raw (string.s:685), `CAT` adds
  lengths (string.s:404), `LEFT$/MID$/RIGHT$` index by byte offset, `CHR$` makes
  a 1-byte string, `ASC` reads one byte.
- **PRINT** (`STRPRT`, print.s:274) loops the bytes and calls `OUTDO → MONCOUT`
  (kernel `CHROUT`) once per byte.
- **Attributes are NOT in the data stream today.** Kernel `chrout` writes the
  tile byte to the nametable and writes the **global** `TEXT_ATTR` (`$0302`) to
  the attribute plane (console.s:196-205). Color today = one current-attribute
  variable, exactly like the C64's "current color."

Zero-page anchors (zeropage.s): `STREND`, `FRETOP`, `FRESPC`, `MEMSIZ`,
`INDEX`, `DSCPTR`, `TEMPST`. Heap strings occupy `[FRETOP .. MEMSIZ)`.

---

## 3. Chosen design

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
`N` (≤ 255). This means **untouched**: `LEN`, string comparison (compares only
the first `N` bytes → style-insensitive, which is the desired default), `ASC`,
`VAL`, the 255 limit, and the descriptor/variable/array storage format.

Why SoA-in-block (not interleaved char,attr pairs, not a twin/parallel heap):

- **Aliasing just works.** `A$ = B$` copies the 3-byte descriptor; both point at
  the same block, so both see the same attrs. No deep copy.
- **GC stays one contiguous move.** `GARBAG` relocates a string as a single run;
  the only change is the span is `2N` instead of `N`.
- **Matches the hardware.** Chars and attrs are each contiguous, mirroring the
  MIA's two separate planes — `PRINT` can blast the char run and the attr run as
  two straight copies instead of striding interleaved pairs.
- **Literals can carry style inline later** (option B) because char+attr stay
  adjacent.

The one cost vs. interleaving: slice/concat must locate the **source's** attr
sub-block, which sits at `source_ptr + source_len`. For a substring that means
the **parent** length — which is already in hand at the call site (`DSCPTR`).
See §3.4.

### 3.2 Allocation — reserve `2N` without a 16-bit length and without a cap

`GETSPA` (string.s:146) computes `FRETOP - A` where the **subtraction is already
16-bit** (it borrows into `FRETOP+1`); only the *amount* `A` is 8-bit. To reserve
`2N` we subtract `N` **twice** — `(FRETOP - N) - N` — with borrows propagating
correctly for `N` up to 255 (→ 510 bytes). So:

- The stored length stays a **single byte** (`N`, ≤ 255). We never need `2N` to
  fit in 8 bits.
- **No 127 cap.** Full 255-char styled strings work.
- Every other place that uses length as a byte count for movement/free uses the
  same "do it with `N` twice" via the existing 16-bit pointer math: `FRETMP`
  (free, string.s:517-522 — add `N` twice), `GARBAG` /
  `MOVE_HIGHEST_STRING_TO_TOP` (span end = `LOWTR + N + N`, string.s:379-384,
  moved by the 16-bit `BLTU2`).

### 3.3 Default attribute & minted strings

`DEFAULT_ATTR = $00` (palette 0 = white on blue, matching the cold-start
`TEXT_ATTR`, memory-map §5). Strings minted without style — `CHR$`, `STR$`,
numeric→string, etc. — fill their attr half with `DEFAULT_ATTR`.

The fill happens once in `STRSPA` (the single allocation chokepoint) via
`fill_attr_default`. **Gotcha:** `STRSPA`/`GETSPA` contractually return `A = N`,
and the literal-copy path (`STRLT2`/`LD399`) uses that `A` as the byte count for
the following `MOVSTR`. So `fill_attr_default` **must preserve `A`** (it saves/
restores it). Forgetting this makes input-buffer→heap literal copies move 0 bytes
— the heap char half stays uninitialized — which manifested as direct-mode
`PRINT "HELLO"` printing nothing while program-mode literals (copied in-place,
no `MOVSTR`) worked.

### 3.4 Slicing & concatenation

`LEFT$/MID$/RIGHT$` already **copy** into a fresh allocation (`STRSPA` +
`MOVSTR1`, string.s:568-598) — they do not alias into the parent. So we add a
**second copy pass** for the attr run. Concretely, after the existing char copy:

- The slice's attr **source** = `parent_ptr + parentLen + start` = `INDEX +
  parentLen`. `parentLen` is still readable at `(DSCPTR),0` (FRETMP doesn't
  touch `DSCPTR`).
- The slice's attr **destination**: after the char `MOVSTR1`, `FRESPC` has
  auto-advanced by `count` (string.s:469-474), so it is **already** at the
  result's attr region.
- So: `INDEX += (DSCPTR),0`, reload `count`, `jsr MOVSTR1` again. ~8 instructions.

`CAT` (string.s:404-433): result attr region starts at the new total length;
each source's attrs are found via that source's own length.

### 3.5 Literals — initial decision (option A)

String literals live in **program text** and have **no attr half**. They render
with `DEFAULT_ATTR`. `PRINT`/`LIST` distinguish a heap string (has an attr half)
from a program-text literal by a **pointer range check** (`ptr` in the heap
`[FRETOP .. MEMSIZ)` → read attrs at `ptr+N`; otherwise use `DEFAULT_ATTR`),
mirroring `STRLT2`'s existing input-buffer check (string.s:88-96).

Programs that use no styling pay **nothing** — backward compatible.

**Phase 6 initial implementation:** per-character styled literals typed into
program lines. Do **not** hide bytes inside quotes or inline the style data in
the executable token stream. Keep the normal tokenized line intact through its
`$00` terminator, then append a Clementina-only **style sidecar** before the next
BASIC line:

```text
[next lo][next hi][line lo][line hi][tokenized text...][$00]
[$CE][$FF][sidecar_len][record_count]
[literal_offset][literal_len][attr0][attr1]...[attrN-1]
...
```

`literal_offset` is the offset of the first literal character within the tokenized
line text (not the opening quote), `literal_len` is the character count, and the
following bytes are raw overlay attribute bytes. The tokenizer records every
non-empty quoted literal while entering a numbered line; lines with no quoted
literals have no sidecar. `$CE,$FF` is the magic marker: `$FF` is impossible as a
next-line pointer high byte in Clementina's `$0000-$7FFF` base-RAM program area,
so old/plain lines will not be misread as styled sidecars.

Runtime rule: when `STRLIT`/`STRLT2` evaluates a program-text literal, look for a
sidecar record covering that literal. If none exists, keep the current fast path:
the descriptor points directly into program text and prints with the default
attribute. If a record exists, allocate a normal styled heap string, copy the
literal bytes into the char half, copy the sidecar attrs into the attr half, and
return that temp. From that point onward, existing styled-string machinery
(`PRINT`, assignment, `CAT`, `LEFT$`/`MID$`/`RIGHT$`) works unchanged.

BASIC line input must not apply the old terminal-era printable-ASCII filter to
Clementina editor harvests. `KERN_EDITKEY` already performs interactive editing
and then doles raw overlay tile bytes from `EDIT_BUF`; `INLIN` stores those bytes
verbatim, using `EDIT_STATE` only to distinguish a harvested `$0D` tile from the
synthetic final RETURN. This is what lets glyph-mode tiles such as `$A1`, `$91`,
`$0D`, or `$02` survive inside quoted program literals.

Editor-harvested bytes outside printable ASCII (`<$20` or `>=$7F`) get
`STRING_RAW_TILE` (`$40`) ORed into their string/sidecar attr byte. That bit is
internal to BASIC string storage, reusing the currently unexposed overlay
priority bit. `styled_outc` checks it to draw control-range tiles raw (including
tile `$0D`) and masks it back out before writing `TEXT_ATTR`, so it never reaches
the overlay attribute plane as priority. Minted strings (`CHR$`, `STR$`,
numeric strings) keep `DEFAULT_ATTR`, so `CHR$(13)` still prints a newline.

Any code that advances between program lines must skip the optional sidecar.
`FIX_LINKS` and sequential execution line advance do this now; `LIST` follows the
rebuilt next-line links and does not print sidecar bytes. `LIST` also renders
quoted literals with their stored attrs, so listing and re-entering a program
preserves visible style naturally through the existing screen harvest. Important
implementation gotcha: `LIST` must preserve `LOWTRX` across `LINPRT` before
scanning for the sidecar, because line-number formatting can clobber that scratch
pointer via the string output path. `LIST` must also treat high bytes inside
quotes as glyphs instead of BASIC tokens. `DATA`/`READ` scanning also skips
sidecars when walking to the next DATA statement.

### 3.6 Present (PRINT)

`STRPRT` (print.s) walks the chars. For a heap (styled) string it combines each
char's stored attr with the BASIC default/policy, writes the effective attr to the
kernel's global `TEXT_ATTR` (`$0302`), then outputs the char. Genuinely unstyled
output — numbers, unstyled literals, messages — has no attr half and prints at the
**BASIC pen** (`@lit`). String literals that were *written* in a color are not
unstyled: they are promoted to heap strings carrying their attrs (a direct-mode
literal via `STRLT2`/`EDIT_ATTR_BUF`, a program literal via
`styled_program_literal_to_heap`) and take the heap path in their written colors.
So `PRINT "FRAN";A` prints `FRAN` in its stored color but the number `A` in the
BASIC pen.

The pen model keeps the **editor pen and the BASIC pen independent** — the editor
pen the user sets with ESC is never clobbered by BASIC output:

- **Editor pen / current pen** — the kernel/editor `TEXT_ATTR` (`$0302`); set from
  the keyboard (ESC commands) and used for the cursor preview, new typed/stamped
  cells, and the color newly typed text is stored with (which is what a string
  literal carries into `PRINT`). It is *persistent*: `STRPRT_STYLED` saves it at
  entry and restores it at every exit, so styled output leaves it unchanged and the
  cursor keeps its color across a `PRINT`.
- **BASIC default attribute / BASIC pen** — `BASIC_DEFAULT_ATTR` (`$03FD`); set by
  `COLOR`/`FLIPX`/`FLIPY`/`ALT` (which no longer touch `TEXT_ATTR`). Used for
  (a) system messages — startup/error/`READY.` text and `INPUT` prompts, which
  `STROUT` prints by loading the BASIC pen into `TEXT_ATTR` and restoring the editor
  pen afterwards — and (b) as the override source for styled strings via the mask.
- **Style policy mask** — `BASIC_STYLE_MASK` (`$03FE`). Effective output attr:

```text
effective = (stored_attr & ~override_mask) | (BASIC_DEFAULT_ATTR & override_mask)
```

`BASIC_STYLE_MASK = $00` means AUTO/use stored sidecar or heap attrs.
`BASIC_STYLE_MASK = $BF` means override palette, flip-X, flip-Y, and CHR_ALT from
`BASIC_DEFAULT_ATTR` while leaving the internal raw-tile bit 6 alone.

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

Output depends on whether the string is a **heap** string (carries an attribute
half — can hold Phase 5 graphic tile codes) or a program-text **literal/message**
(no attr half, plain unstyled text):

- **Literals/messages → plain `OUTDO`** (the pre-Phase-5 behavior). They contain
  CR/LF formatting that `chrout` must interpret — message strings begin with a
  CR+LF and the LF (`$0A`) must be *ignored*. Drawing those raw would stamp a blank
  LF glyph at column 0 of every message line (the bug that shipped briefly).
- **Heap strings → `styled_outc`.** Graphic tile codes `$80–$FF` (and mode-2 wraps
  into `$00–$3E`) collide with `chrout`'s control codes (`$0D` CR,
  `$11/$13/$1D/$91/$9D` cursor moves). Plain text `$20-$7E` goes through `OUTDO`
  (keeps `Z14`/`POSX` bookkeeping). Untagged `$0D` remains newline (`OUTDO` +
  `PRINTNULLS`, so `CHR$(13)` still breaks lines). Tagged control-range bytes and
  all other non-plain bytes are drawn as **raw tiles** via
  `MONCOUT_GLYPH → KERN_CHROUT_GLYPH` (`$0427`), advancing `POSX` one column and
  honoring `Z14`.

See [phase5-charset-keyboard.md §6.1](phase5-charset-keyboard.md). Remaining
literal-storage limit: tile `$00` cannot be represented directly inside stored
BASIC source text because `$00` terminates a tokenized line.

### 3.7 Capture (INPUT / screen editor)

Mechanism (Phase 4):

1. **Harvest** — `harvest_line` (editor.s) already reads the overlay nametable
   into `EDIT_BUF` via index `$B8`. It now also reads the matching **attribute
   plane** cells into a parallel `EDIT_ATTR_BUF` (kernel RAM at `$0380`, 80
   bytes, in the free `$0380–$03FF` region). Same start cell, same count.
2. **Alignment** — BASIC's `INLIN` stores the doled chars at `INPUTBUFFER,x`
   from `x = 0` (inline.s), and the editor doles `EDIT_BUF` from index 0, so
   `EDIT_ATTR_BUF[k]` is the attribute of `INPUTBUFFER[k]`. For Clementina,
   `INLIN` trusts this already-edited stream and stores raw glyph bytes, including
   high bytes and control-range tiles, instead of filtering to printable ASCII.
3. **Route into the string** — the input-buffer→heap literal copy (`STRLT2`/
   `LD399`, taken when the literal lives in zero-page = the input buffer) copies,
   after the character `MOVSTR`, `N` attribute bytes from
   `EDIT_ATTR_BUF + (STRNG1 − INPUTBUFFER)` into the new string's attribute half
   (`FRESPC`, already positioned at `base + N`). This overrides the
   `DEFAULT_ATTR` fill for input-buffer strings only; minted strings (`CHR$`,
   `STR$`) keep the default fill. Program-text literals (`PUTNEW`, no `MOVSTR`)
   are unaffected → still `DEFAULT_ATTR` (option B territory).

Source of non-default attributes during typing: the kernel paints typed cells
with the current `TEXT_ATTR`. Phase 5 now sets that pen from the keyboard
(`ESC 0–F` color, `ESC R/H/V` reverse/flip, `ESC P` Paint mode — see
[phase5-charset-keyboard.md](phase5-charset-keyboard.md)); it can still be set
programmatically with `POKE 770,n` (770 = `$0302` = `TEXT_ATTR`). `READ`/`DATA`
come from program text → `DEFAULT_ATTR`.

Test: `10 POKE 770,5` / `20 INPUT A$` / `30 PRINT A$`, RUN, type text → it should
print back in palette 5 (the `?` prompt is drawn via `OUTDO`, which does not
reset `TEXT_ATTR`, so the pen survives into the editor).

### 3.8 Charset (parallel track) — see Phase 5 spec

Default 1bpp charset using **two banks**: bank 0 = regular glyphs, bank 1 =
reversed (0/1 swapped) at the **same** positions; "reverse" = the CHR_ALT
attribute bit. **Superseded detail:** the original "C64 SHIFT/COMMODORE held
combinations select glyphs" idea was dropped — held modifiers corrupt the FIFO
byte (host composition/suppression), so glyph selection is instead done
kernel-side via three *glyph modes* on clean ASCII, plus an ESC-prefix command
layer for color/flip/reverse. Full design (input model, attribute bits, modes,
commands, Paint mode, cursor indicators, charset tile map) is the authoritative
[phase5-charset-keyboard.md](phase5-charset-keyboard.md). Authoring via
`tools/tile-editor.html`.

---

## 4. Change map (files)

| File | Change |
| --- | --- |
| `src/basic/string.s` | `GETSPA` reserve `2N` (subtract `N` twice) + OOM retry; `STRSPA`; `MOVSTR`/`MOVSTR1` copy attr run; `FRETMP` free `2N`; `GARBAG`/`MOVE_HIGHEST_STRING_TO_TOP` span `N+N`; `CAT`; `CHRSTR` + other minted strings fill `DEFAULT_ATTR`; `LEFTSTR`/`RIGHTSTR`/`MIDSTR` second copy pass; literal range marker in `STRLT2` |
| `src/basic/print.s` | `STRPRT` per-char `TEXT_ATTR`; heap-vs-literal range check |
| `src/basic/var.s` | string `LET` — descriptor copy fine (aliasing safe); heap allocations get attr halves |
| `src/basic/input.s` / token | `INPUT` capture of attrs |
| `src/kernel/editor.s` | harvest overlay attribute plane into `EDIT_ATTR_BUF` |
| `src/kernel/console.s` | optional reverse-as-alt-bank in `chrout`; per-char `TEXT_ATTR` already supported |
| `src/basic/defines_clementina.s` | `STYLED_STRINGS` flag, `DEFAULT_ATTR` |
| charset assets + `tools/tile-editor.html` | two-bank 1bpp font + glyph-mode/ESC styling workflow |
| Future Phase 6 | `program.s` tokenizer/LIST/line traversal, `string.s` literal evaluation, `clementina_extra.s`/`print.s` default/style policy, `defines_clementina.s` runtime defaults |

**Untouched:** `LEN`, comparison, `ASC`, `VAL`, descriptor layout, 255 limit,
variable/array storage.

---

## 5. Open questions

- ~~Exact heap-vs-literal boundary for the range check.~~ **Resolved: `FRETOP`.**
  `STRPRT_STYLED` classifies a string as heap (has an attr half) when its data
  pointer is `>= FRETOP`. `STREND` does **not** work: with
  `CONFIG_SCRTCH_ORDER = 2`, the cold-start "BYTES FREE" message prints *before*
  `SCRTCH` initializes `STREND` ([init.s:420-426](../src/basic/init.s#L420)), so
  an `INDEX >= STREND` test reads garbage and styles the startup messages with
  random flip/palette bits. `FRETOP` is set to `MEMSIZ` far earlier
  ([init.s:303](../src/basic/init.s#L303)), so it is always valid.
  **Caveat (resolved in Phase 1c):** `STRPRT` calls `FREFAC`, which frees a
  printed *temp* before classification, raising `FRETOP` above it. A freed temp
  keeps its bytes (incl. its attr half), so the fix is to *classify before the
  free*: `STRPRT` snapshots `FRETOP` into `DEST` *before* `FREFAC`, and
  `STRPRT_STYLED` classifies the data pointer against that snapshot. The same
  "classify before the free" rule is applied in slicing/`CAT` (`classify_heap`
  runs while the source is still live, against the live `FRETOP`).
- Style-sensitive comparison? Default **no** (compare chars only). Revisit if a
  use case appears.
- Memory budget: styled strings cost 2× heap inside BASIC's `$3601–$BFFF`
  workspace, whose upper 16 KiB is Extended RAM bank 0. Relocating the attr half
  to a separate bank remains rejected due to bank-switch cost inside GC.
- Phase 6 styled program literals: sidecar format, line-skip helper, `LIST`
  rendering, `$0D` raw-glyph disambiguation, and `DATA`/`READ` sidecar walking
  are implemented. Remaining work: runtime default/style policy; see §3.5/§3.6.

---

## 6. Execution plan (phased)

Status as of 2026-06-24. The emulator embeds `kernel.bin` at compile time, so
after `make install` the emulator must be **rebuilt** (`go run`), not just reset.

- **Phase 0 — foundations — DONE.** This doc, plus `STYLED_STRINGS`,
  `DEFAULT_ATTR`, and `TEXT_ATTR` in `defines_clementina.s`. Builds.
- **Phase 1a — `2N` size agreement — DONE, emulator-validated.** `GETSPA`
  reserves `2N` (stack-peek double subtract); `MOVE_HIGHEST_STRING_TO_TOP`
  relocates `2N`; `FRETMP` frees `2N`. Validated: `FRE(0)=19276`, GC stress
  clean, all string ops correct. Attr half was dead at this point.
- **Phase 1b — default-fill attr half — DONE.** `fill_attr_default` (in
  `string.s`) hooked into `STRSPA`. Two bugs fixed here: (1) `tya` clobbering the
  fill value → gradient garbage; (2) clobbering `A`, which broke the literal-copy
  `MOVSTR` byte count (see §3.3 gotcha) → direct-mode strings came up empty.
- **Phase 2 + 3 — present + classify — DONE (working in emulator).**
  `STRPRT` → absolute `jmp STRPRT_STYLED` (routine lives in the `EXTRA` segment,
  `clementina_extra.s`, to dodge `CODE`-segment branch-range limits). Classifies
  by `INDEX >= FRETOP` (not `STREND` — uninitialized at cold start, see §5);
  heap → per-char `TEXT_ATTR`, literal → `DEFAULT_ATTR`. With all attrs default,
  output is plain white and correct.
- **Phase 1c — propagate real attrs — DONE (emulator-validated).**
  `LEFT$`/`MID$`/`RIGHT$` add a second copy pass (`slice_attrs`) and
  `CAT` appends both source attr runs (`cat_attrs`), each source's attrs found at
  `source_ptr + source_len`. A shared `append_attr_run` copies the run for heap
  sources or steps `FRESPC` over it (keeping the default fill) for program-text
  literals. `classify_heap` distinguishes the two *before* any free (a freed temp
  keeps its bytes; only the address test would lie). Freed-temp classification in
  `STRPRT` fixed via the `DEST` = pre-`FREFAC` `FRETOP` snapshot. Scratch: `DEST`
  (block-move pointer, free in these windows; set after any GC inside `STRSPA`).
- **Phase 4 — capture — DONE (emulator-validated).**
  4a: `harvest_line` (editor.s) reads the overlay attribute plane into
  `EDIT_ATTR_BUF` (`$0380`, parallel to `EDIT_BUF`). 4b: the input-buffer→heap
  copy (`LD399`, string.s) routes `N` attr bytes from
  `EDIT_ATTR_BUF + (STRNG1 − INPUTBUFFER)` into the new string's attr half (over
  the `DEFAULT_ATTR` fill). First point where styling originates from typing.
- **Phase 5 — charset + keyboard glyph entry — PARTLY IMPLEMENTED
  (2026-06-24).** Full spec in
  [phase5-charset-keyboard.md](phase5-charset-keyboard.md):
  256 glyphs in two banks (bank 0 normal, bank 1 reversed; reverse = CHR_ALT);
  3 kernel-side glyph modes (`tile = (ascii + mode*$60) & $FF`); pen =
  `TEXT_ATTR` bits (palette/flip-X/flip-Y/reverse); ESC-prefix command layer +
  Paint mode; cursor = live pen preview (8 indicator tiles `$F8–$FF`). FIFO-only
  and source-agnostic (WiFi/USB-host/console). 5a-5e are done; 5f (console ANSI
  decoder) is deferred.
- **Phase 6 — styled program literals + BASIC style defaults — IMPLEMENTED.**
  Stores literal attrs in the program-line sidecar described in §3.5. Runtime
  `BASIC_DEFAULT_ATTR` + `BASIC_STYLE_MASK` are controlled by `COLOR`, `FLIPX`,
  `FLIPY`, `ALT`, and `STYLE n` (§3.6).
- **Phase 7 — editor pen / BASIC pen independence — IMPLEMENTED.** BASIC no
  longer overwrites the editor pen. `COLOR`/`FLIPX`/`FLIPY`/`ALT` set
  `BASIC_DEFAULT_ATTR` only (dropped the `sta TEXT_ATTR` sync). `STRPRT_STYLED`
  saves the pen at entry and restores it at every exit (heap loop no longer resets
  to the BASIC default). Unstyled output (numbers, unstyled literals) prints at the
  BASIC pen (`@lit`); string literals written in a color are promoted to heap
  strings and keep their written colors (heap path), so `PRINT "FRAN";A` prints
  `FRAN` in its stored color and the number `A` in the BASIC pen. System messages
  route through `STROUT`, which loads `BASIC_DEFAULT_ATTR` into `TEXT_ATTR` for the
  message and restores the editor pen after. The whole error line is set to the
  BASIC pen at the top of `ERROR` (so the `?<name>` prefix matches the `ERROR`
  suffix); the cursor is an
  input-time construct redrawn only by `chrin`, and the editor reasserts
  `EDITOR_PEN` (`$0304`) into `TEXT_ATTR` at each line edit so its color survives
  any BASIC output (LIST/errors/styled PRINT). Emulator-validated
  (`TestPenIndependence`, `TestUnstyledNumberUsesBasicPen`,
  `TestErrorMessageUsesBasicPen`, `TestCursor*`, `pkg/computers/clementina`).
  Note: `COLOR` governs system messages and the styled-string override source, not
  the color of typed text (that is the editor pen, carried by the string literal).

Verification: `make` builds `build/kernel.bin`; `make install` copies it into the
emulator asset; then rebuild the emulator (`go run`) to re-embed it.

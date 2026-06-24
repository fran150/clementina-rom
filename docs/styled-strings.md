# Styled strings — per-character attributes in BASIC strings

Status: **capture working end-to-end through Phase 4 — emulator-validated**
(2026-06-23). Phases 0–4 + 1c done; next is Phase 5 (charset). Validated with
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

**Option B (deferred):** per-character styled literals typed into program lines.
Requires storing the literal's attrs inside the tokenized program (a run-length
blob next to the literal) and copying styled literals into the heap *with* their
attrs when referenced (giving up the in-place optimization for styled literals
only; plain literals keep the fast path). Touches the tokenizer, `LIST`,
`SAVE`/`LOAD`. Not in the initial scope.

### 3.6 Present (PRINT) — no kernel change required

`STRPRT` (print.s:274) walks the chars. For each char `i`: write `attr(i)` to the
kernel's global `TEXT_ATTR` (`$0302`), then `OUTDO` the char (kernel `chrout`
paints char + current `TEXT_ATTR`). Restore the prior `TEXT_ATTR` after the
string. For program-text literals (no attr half) just leave `TEXT_ATTR` at the
default. This reuses the existing `chrout` path unchanged.

### 3.7 Capture (INPUT / screen editor)

Mechanism (Phase 4):

1. **Harvest** — `harvest_line` (editor.s) already reads the overlay nametable
   into `EDIT_BUF` via index `$B8`. It now also reads the matching **attribute
   plane** cells into a parallel `EDIT_ATTR_BUF` (kernel RAM at `$0380`, 80
   bytes, in the free `$0380–$03FF` region). Same start cell, same count.
2. **Alignment** — BASIC's `INLIN` stores the doled chars at `INPUTBUFFER,x`
   from `x = 0` (inline.s), and the editor doles `EDIT_BUF` from index 0, so
   `EDIT_ATTR_BUF[k]` is the attribute of `INPUTBUFFER[k]`. No `INLIN` change.
3. **Route into the string** — the input-buffer→heap literal copy (`STRLT2`/
   `LD399`, taken when the literal lives in zero-page = the input buffer) copies,
   after the character `MOVSTR`, `N` attribute bytes from
   `EDIT_ATTR_BUF + (STRNG1 − INPUTBUFFER)` into the new string's attribute half
   (`FRESPC`, already positioned at `base + N`). This overrides the
   `DEFAULT_ATTR` fill for input-buffer strings only; minted strings (`CHR$`,
   `STR$`) keep the default fill. Program-text literals (`PUTNEW`, no `MOVSTR`)
   are unaffected → still `DEFAULT_ATTR` (option B territory).

Source of non-default attributes during typing: the kernel paints typed cells
with the current `TEXT_ATTR`. Until a key-driven attribute selector exists
(Phase 5), set it programmatically — `POKE 770,n` (770 = `$0302` = `TEXT_ATTR`).
`READ`/`DATA` come from program text → `DEFAULT_ATTR`.

Test: `10 POKE 770,5` / `20 INPUT A$` / `30 PRINT A$`, RUN, type text → it should
print back in palette 5 (the `?` prompt is drawn via `OUTDO`, which does not
reset `TEXT_ATTR`, so the pen survives into the editor).

### 3.8 Charset (parallel track)

Default 1bpp charset using **two banks**: bank 0 = regular glyphs, bank 1 =
reversed (0/1 swapped) at the **same** positions. C64-style `SHIFT`/`COMMODORE`
key combinations select glyphs. "Reverse" maps naturally onto the alternate-bank
attribute bit (equivalently the high bit of the tile code, C64 screen-code
style) and can be handled in `chrout`. Authoring via `tools/tile-editor.html`.

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
| charset assets + `tools/tile-editor.html` | two-bank 1bpp font + key combos |

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
- Memory budget: styled strings cost 2× heap inside `$3000–$8000`. Option to
  relocate the attr half to banked Extended RAM (`$8000–$BFFF`) later — rejected
  for now due to bank-switch cost inside GC.
- Option B (styled literals) tokenizer/LIST/SAVE format. Deferred.

---

## 6. Execution plan (phased)

Status as of 2026-06-23. The emulator embeds `kernel.bin` at compile time, so
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
- **Phase 5 — charset:** two-bank 1bpp font + C64-style key combos;
  reverse-as-alt-bank in `chrout`.
- **Phase 6 (optional) — option B styled literals.**

Verification: `make` builds `build/kernel.bin`; `make install` copies it into the
emulator asset; then rebuild the emulator (`go run`) to re-embed it.

# Clementina BASIC — Video

Clementina BASIC drives the parts of MIA's video hardware that `COLOR`/
`BCOLOR`/`FLIPX`/`FLIPY`/`ALT`/`STYLE` don't reach: the background (playfield)
layer, sprites, CHR bank/plane configuration, palette RAM, and the overlay
layer's whole-layer/whole-screen switches. Like the sound statements, these are
thin: each one parses its arguments and writes MIA's render-control registers,
then returns.

The chip model (render-control field layout, the eight raw BG tables, OAM, CHR
banks/planes) is derived from the actual renderer,
[`clementina-video-client` `internal/render/renderer.go`](../../../clementina-video-client/internal/render/renderer.go),
cross-checked against the index wiring in both the emulator
(`clementina-6502` `pkg/components/mia/video.go`) and the real firmware
(`clementina-mia` `src/mia/video/video.c`), which configure the identical set
of index descriptors. This page is the BASIC programmer's reference; see
[memory-map.md §12](memory-map.md) for the kernel's own (much smaller) use of
the overlay layer.

## Model

- **Three layers**, composited bottom to top: **background**, then any
  BG cell drawn with its priority attribute set, then **sprites**, then the
  **overlay** (the BASIC text console). `LAYER_ENABLE` bits turn each on/off
  independently; `VIDEO_MODE` turns the whole picture on/off.
- **Background** is a scrollable playfield built from up to eight raw 40×25
  tile tables (nametable + attribute byte per cell). `BGMODE` picks how those
  tables tile together into one canvas (1×, 2×, or 4× the 320×200 viewport,
  horizontally, vertically, or both); `BGSET` swaps to a second complete set of
  tables (index +4) for flicker-free map swaps; `SCROLL` pans the fixed
  320×200 viewport across that canvas, wrapping at its edges.
- **Sprites** are OAM entries (tile, X, Y, palette, flip, priority, enable),
  positioned independently and clipped at the screen edge.
- **CHR banks** hold tile/glyph graphics: 8 banks, each either 3bpp (8 colors)
  or 1bpp (2 colors, picking one of the bank's 3 planes). BG, sprites, and the
  overlay each have their own current bank (+ an alt bank for BG/overlay,
  selected per-cell by the `CHR_ALT` attribute bit).
- **Palette** is 16 banks of 8 RGB565 colors. The attribute byte's low nibble
  picks the bank; the pixel's decoded color index (0-7, or 0/1 in 1bpp mode)
  picks the color within it.

## Statements — Phase 1 (implemented)

Direct register wrappers: parse args (`ILLEGAL QUANTITY` on out-of-range,
same as `COLOR`), write MIA's render-control page or palette RAM.

| Statement | Arguments | Effect |
| --- | --- | --- |
| `BGON` / `BGOFF` | — | Background layer on/off (`LAYER_ENABLE` bit 0). |
| `SPRON` / `SPROFF` | — | Sprite layer on/off (`LAYER_ENABLE` bit 2). Per-sprite show/hide is a `SPRITE` field (Phase 2), not a separate verb. |
| `VIDON` / `VIDOFF` | — | Whole video output on/off (`VIDEO_MODE` bit 0). |
| `BGMODE n` | `n` 0-5 | BG viewport mode: `0` 40×25 (no scroll headroom), `1` 80×25, `2` 40×50, `3` 160×25, `4` 40×100, `5` 80×50 - cell counts for the *virtual scrollable map*, not the display resolution (always 320×200). |
| `BGSET n` | `n` 0 or 1 | Selects which of the two BG table sets the current `BGMODE` arrangement reads. |
| `SCROLL x,y` | `x,y` 0-65535 | BG layer pixel scroll. Wraps at the current mode's canvas size. |
| `BGBANK n` / `BGALT n` | `n` 0-7 | CHR bank the BG layer draws from normally / where a cell's `CHR_ALT` bit is set. |
| `SPRBANK n` | `n` 0-7 | CHR bank sprites draw from. |
| `SPRCOUNT n` | `n` 0-255 | Highest OAM index the renderer scans each frame. |
| `CHRMODE bank,flag` | `bank` 0-7, `flag` 0/non-zero | Mark a CHR bank as 1bpp (`flag<>0`) or 3bpp (`flag=0`). |
| `CHRPLANE bg,spr,ovl` | each 0-3 | Which of a 1bpp bank's 3 planes each layer decodes (only matters for banks `CHRMODE` marked 1bpp). |
| `PALETTE bank,index,r,g,b` | `bank` 0-15, `index` 0-7, `r`/`b` 0-31, `g` 0-63 | Write one palette RGB565 entry directly (palette fades/cycling at runtime - nothing else can change palette RAM after boot). |

Boot state (`video_init`, `src/kernel/video.s`): overlay layer on, background
and sprites off; CHR banks 0/1 both 1bpp (overlay plane 1); BG/sprite CHR
banks default to bank 0.

## Statements — Phase 2 (implemented)

The DATA-stream bulk-read primitive (`vid_data_byte` in `clementina_extra.s`):
advance `DATPTR`, pull one numeric item via the same path `READ` uses, write it
to an auto-incrementing MIA address - skipping the per-iteration BASIC
interpreter overhead a hand-rolled `FOR...READ...POKE...NEXT` loop would pay.
It works by *borrowing the real `READ` statement*: point `TXTPTR` at a
reserved scratch variable's name (`Z9`) and `jsr READ` (so `Z9` = the next
`DATA` value and `DATPTR` advances exactly as a real `READ` would, including a
real `?OUT OF DATA` error when the program runs out), then re-evaluate `Z9` via
`GETBYT` to get it as a byte. `Z9`'s value is saved and restored around the
whole bulk command, so nothing user-visible changes except that a variable
named `Z9` exists afterward - avoid using it in a program that also calls one
of the `*LOAD` statements below.

`vid_data_byte` calls into the interpreter's own `READ`/`GETBYT`, which use `Y`
freely as working state - **`Y` does not survive a call to it** (nor to
`vid_wr_abs`/`vid_wr_abs2`, which sidesteps the problem by carrying its stream
selector through a scratch byte instead of a register). `vid_bulk_run`'s
field-within-item loop learned this the hard way: keeping the index in `Y`
across `jsr vid_data_byte` silently corrupted it for every multi-stream
command, which single-stream commands (`VID_STREAM2=0`) masked completely
(`0 AND anything` is always `0`, so the stream decision came out right by
accident) - only `BGLOAD` (since split into `NTREAD`/`ATRREAD` - see below),
the one genuine multi-stream user, exposed it. The
field index lives in a dedicated byte (`VID_FIELD`) now, reloaded into `Y`
fresh right before the one instruction that needs it.

| Statement | Arguments | Effect |
| --- | --- | --- |
| `BGCHAR col,row,tile,attr` | `col`/`row` map-relative for the current `BGMODE` (e.g. 0-159/0-24 in mode 3) | Write one BG nametable+attribute cell, mode-aware - resolves which of the 8 raw tables and where in it, replaying `bgTableAndLocal`'s math (see below). Out-of-range `col`/`row` raises `ILLEGAL QUANTITY` rather than wrapping. |
| `NTREAD table,cell,count` | `table` 0-7, `cell` 0-999, `count` 0-65535 | Bulk-load `count` raw nametable (tile) bytes from `DATA` into raw BG table `table`, starting at `cell`. |
| `ATRREAD table,cell,count` | same ranges as `NTREAD` | As `NTREAD`, but the attribute half of the table - a separate call over its own run of `DATA` values, continuing the shared stream where the last `READ`/`NTREAD`/etc. left it. |
| `CHRREAD bank,offset,count` | `bank` 0-7, `offset` 0-6143, `count` 0-65535 | Bulk-load `count` raw tile/graphics bytes from `DATA` into CHR bank `bank`. |
| `PALREAD bank,offset,count` | `bank` 0-15, `offset` 0-15, `count` 0-255 | Bulk-load `count` raw palette bytes from `DATA`, starting `offset` bytes into bank `bank`. |
| `OAMREAD n,count` | `n` 0-255, `count` 0-255 | Bulk-load `count` sprites' raw 5-byte records (`tile,xlo,ylo,attr,ext`) from `DATA`, starting at OAM index `n`. |
| `SPRITE n,tile,x,y,pal,flags` | `n`/`tile` 0-255, `x` -512..511, `y` -256..255, `pal` 0-15, `flags` bit0 disable/bit1 priority/bit2 flip-X/bit3 flip-Y | Full per-sprite setup in one call. |
| `SPRX n,x` / `SPRY n,y` | same ranges as `SPRITE`'s `x`/`y` | Change one sprite's position only - cheap per-frame animation update without respecifying every `SPRITE` field. |
| `SPRTILE n,t` | `t` 0-255 | Change one sprite's tile/frame index only. |
| `SPRCOLOR n,pal` | `pal` 0-15 | Change one sprite's palette only. |
| `SPRFLIP n,fx,fy` | each 0/non-zero | Change one sprite's flip-X/flip-Y only. |
| `SPRPRI n,p` | 0/non-zero | Change one sprite's priority only. |

**Renamed in the file-I/O work (2026-09):** these five were originally named
`BGLOAD`/`CHRLOAD`/`PALLOAD`/`OAMLOAD` (`BGLOAD` doing both halves of a BG
table in one interleaved call). The bare names now mean "load from an SD
file" instead - matching `LOAD`'s real meaning - with `NTLOAD`/`CHRLOAD`/
`PALLOAD`/`OAMLOAD` and their `*SAVE` counterparts documented in
[docs/basic-file.md](basic-file.md) alongside the rest of Clementina's file
I/O. The table above is current; `BGLOAD`/the old `CHRLOAD` etc. no longer
exist as such.

### `BGCHAR`'s mode math

`BGCHAR` ports the renderer's `bgTableAndLocal` (see the Model section above)
into 6502: read the current `BG_VIEWPORT_MODE`/`BG_ACTIVE_SET`, range-check
`col`/`row` against that mode's canvas size, divide by 40/25 (`divmod40`/
`divmod25` - repeated subtraction, since `col`/`row` are always small enough
that this never loops more than 3-4 times) to get a per-table quotient and a
local cell offset, fold the quotient into a table index the same way each
`BGMODE` does (`col/40` for modes 1 and 3, `row/25` for mode 4, `(row/25)*2 +
col/40` for mode 5, `(row/25)*2` for mode 2, always `0` for mode 0), add
`BG_ACTIVE_SET*4`, then write through `bg_seek_nt`/`bg_seek_attr` exactly like
`NTREAD`/`ATRREAD` (originally `BGLOAD`) do for a single cell.

### Fitting it: growing the ROM's code budget

The ROM's combined kernel+BASIC code image has a fixed ceiling before a
background-PLAY control block and BASIC's own workspace (`RAMSTART2`) - **not**
a 6502/65C02 hardware limit (the CPU addresses a full 64K; the linker's own
`MAIN` region allows up to 31 KiB) but a deliberately-chosen, and deliberately
movable, software convention: see `Makefile`'s `MAX_KERNEL_BYTES`,
`defines_clementina.s`'s `RAMSTART2`, and `clementina_extra.s`'s `BGP_BASE` -
all three carry a comment inviting exactly this. The first Phase 2 pass landed
`OAMLOAD`/`SPRITE` at the old ceiling (`$4400`/16384 bytes) with zero bytes to
spare, cutting five other commands to fit. Rather than keep squeezing, the
boundary was raised by 2 KiB (`$4400`→`$4C00`, `MAX_KERNEL_BYTES`
16384→18432), trading a small, deliberately generous slice of BASIC's ~29 KiB
free workspace for headroom, and every cut command was restored plus `BGCHAR`
(never previously implemented) and the five single-field sprite setters. Two
other repos mirror this boundary in test code and needed the same bump:
`clementina-6502` `pkg/computers/clementina/background_play_test.go`
(`addrBGPFlags`) and `guessing_game_test.go` (the CPU-runaway sanity check's
upper bound) - grep both repos for the old hex value before moving it again.

Bump `MAX_KERNEL_BYTES`/`RAMSTART2`/`BGP_BASE` together, in lockstep, if more
commands land later.

> **Since raised again** (2026-09, `$4C00`→`$5C00`/`18432`→`22528`) for the
> SD/FS file I/O command set - see [docs/basic-file.md](basic-file.md) and
> [memory-map.md §7.5/§8](memory-map.md). The `$4400`/`$4C00`/`18432`/`16384`
> figures above are that step's own history, not the current values.

## Register reference

Render-control page (32 bytes, MIA RAM `$00020-$0003F`), reached by binding
window A to `VIDX_RENDER_CONTROL` ($80) and repositioning its current address
via `CFG_IDXA_ADDR_L/M/H` (`vid_seek` in `clementina_extra.s` - the same trick
`snd_seek` uses for the audio block):

| Offset | Field | Bytes |
| --- | --- | --- |
| `$00` | `VIDEO_MODE` (bit 0 = enable) | 1 |
| `$01` | `LAYER_ENABLE` (bit0 bg, bit1 overlay, bit2 sprite) | 1 |
| `$02` | `BG_VIEWPORT_MODE` | 1 |
| `$03` | `BG_ACTIVE_SET` | 1 |
| `$04-05` | `SCROLL_X` (LE) | 2 |
| `$06-07` | `SCROLL_Y` (LE) | 2 |
| `$08` | `BG_CHR_BANK` | 1 |
| `$09` | `BG_ALT_CHR_BANK` | 1 |
| `$0A` | `OVERLAY_CHR_BANK` | 1 |
| `$0B` | `OVERLAY_ALT_CHR_BANK` | 1 |
| `$0C` | `SPRITE_CHR_BANK` | 1 |
| `$0D` | `CHR_1BPP_MASK` (bit n = bank n is 1bpp) | 1 |
| `$0E` | `CHR_1BPP_PLANES` (bg[1:0] spr[3:2] ovl[5:4]) | 1 |
| `$0F` | `BACKDROP_COLOR` (also `VIDX_BACKDROP_COLOR`/`BCOLOR`) | 1 |
| `$10` | `OAM_LAST_INDEX` | 1 |

Other regions, each its own index descriptor(s):

| Region | Index(es) | Size |
| --- | --- | --- |
| Palette | `$90-$9F` (bank 0-15) | 16 bytes/bank (8 colors × RGB565) |
| CHR banks | `$A0-$A7` (bank 0-7) | 6144 bytes/bank (3 planes × 2048) |
| BG nametables | `$A8-$AF` (table 0-7) | 1000 bytes/table |
| BG attributes | `$B0-$B7` (table 0-7) | 1000 bytes/table |
| Overlay nametable/attributes | `$B8`/`$B9` | 1000 bytes each |
| OAM | `$C0-$DF` direct (32 of 256 entries); full 256 reachable via absolute addressing | 5 bytes/entry |

Attribute byte formats (BG/overlay cells vs. sprites - **not** the same bit
layout):

| | palette | flip X | flip Y | priority | alt bank / disable |
| --- | --- | --- | --- | --- | --- |
| BG/overlay attr | bits 0-3 | bit 4 | bit 5 | bit 6 | bit 7 = `CHR_ALT` |
| Sprite `attr` (OAM byte 3) | bits 0-3 | bit 5 | bit 6 | bit 4 | - |
| Sprite `ext` (OAM byte 4) | - | - | - | - | bits 0-1 = X hi, bit 2 = Y hi, bit 3 = disable |

## Execution plan

- **Phase 1 - IMPLEMENTED (2026-09-11).** Layer toggles, `BGMODE`/`BGSET`/
  `SCROLL`, CHR bank selection (`BGBANK`/`BGALT`/`SPRBANK`), `SPRCOUNT`,
  `CHRMODE`/`CHRPLANE`, `PALETTE`, `VIDON`/`VIDOFF`. All direct register
  wrappers; no firmware/emulator changes needed (the index wiring already
  existed identically on both sides). Emulator-validated: see
  `basic_video_phase1_test.go` in `clementina-6502`
  `pkg/computers/clementina`.
- **Phase 2a - IMPLEMENTED (2026-09-11), reduced scope.** `OAMLOAD` and
  `SPRITE` only, landed at the ROM's then-16 KiB code ceiling with zero bytes
  to spare - `BGLOAD`/`CHRLOAD`/`PALLOAD`/`BGCHAR`/the single-field sprite
  setters were all cut to fit. Emulator-validated:
  `basic_video_phase2_test.go` in `clementina-6502`
  `pkg/computers/clementina`.
- **Phase 2b - IMPLEMENTED (2026-09-12).** Everything cut from 2a, restored
  after raising the code ceiling by 2 KiB (see "Fitting it" above) - `BGLOAD`,
  `CHRLOAD`, `PALLOAD`, `BGCHAR` (newly written, not merely restored), and
  `SPRX`/`SPRY`/`SPRTILE`/`SPRCOLOR`/`SPRFLIP`/`SPRPRI`. Found and fixed two
  real bugs restoring the dual-stream (`VID_ADDR`/`VID_ADDR2`) machinery
  `BGLOAD` needs: `vid_wr_abs` was carrying its stream selector through `Y`,
  clobbering callers' own loop counters (`SPRITE`'s write loop, `vid_bulk_run`'s
  field loop) that relied on `Y` surviving the call; and `vid_bulk_run` itself
  read `Y` for its stream-selection bitmask check *after* a call that also
  clobbers `Y` (`vid_data_byte`, which goes through the interpreter's own
  `READ`/`GETBYT`) - masked completely for every single-stream command by
  `0 AND anything = 0`, so only `BGLOAD` (the one multi-stream user) exposed
  it. Emulator-validated: `basic_video_phase2b_test.go` in `clementina-6502`
  `pkg/computers/clementina`, covering every `BGMODE` branch of `BGCHAR`'s
  table math, `BGLOAD`'s two parallel streams, and that the single-field
  sprite setters touch only their own bits. Full existing suite (both repos)
  still green throughout.
- **File I/O rename - IMPLEMENTED (2026-09).** `BGLOAD` split into `NTREAD`
  (nametable half) + `ATRREAD` (attribute half); `CHRLOAD`/`PALLOAD`/`OAMLOAD`
  renamed to `CHRREAD`/`PALREAD`/`OAMREAD` for their existing DATA-sourced
  behavior. The bare names `NTLOAD`/`CHRLOAD`/`PALLOAD`/`OAMLOAD` were then
  reused for a new, file-sourced meaning (load from an SD file), with
  matching `*SAVE` counterparts - part of the broader SD/FS file I/O work.
  See [docs/basic-file.md](basic-file.md) for the full statement list and
  rationale; the code-budget knobs bumped again for it (see "Fitting it"
  above). Emulator-validated: `basic_video_phase2b_test.go` (updated) and
  `basic_video_phase2_test.go` (updated) in `clementina-6502`
  `pkg/computers/clementina`.

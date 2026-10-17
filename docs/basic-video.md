# Clementina BASIC — Video

Clementina BASIC drives the parts of MIA's video hardware that `COLOR`/
`BCOLOR`/`FLIPX`/`FLIPY`/`ALT`/`STYLE` don't reach: the background (playfield)
layer, sprites, CHR bank/plane configuration, palette RAM, and the overlay
layer's whole-layer/whole-screen switches. Like the sound statements, these are
thin: each one parses its arguments and writes MIA's render-control registers,
then returns.

The video model below is the video client's renderer
([`clementina-video-client` `internal/render/renderer.go`](https://github.com/fran150/clementina-video-client/blob/main/internal/render/renderer.go)).
The register and memory layout is in clementina-sdk:
[`docs/architecture/video.md`](https://github.com/fran150/clementina-sdk/blob/main/docs/architecture/video.md)
has the video RAM map and the attribute bits,
[`specs/video.json`](https://github.com/fran150/clementina-sdk/blob/main/specs/video.json)
(`renderControl`) every render-control field, and
[`specs/mia-indexes.json`](https://github.com/fran150/clementina-sdk/blob/main/specs/mia-indexes.json)
the index ids. The kernel's own use of the overlay is in
[memory-map.md §12](memory-map.md). How these statements were added is in
[history/basic-video.md](history/basic-video.md).

## Model

- **Layers**, composited bottom to top: the **backdrop** color, the
  **background**, **sprites**, then the background pixels whose cell has the
  priority bit set, then the **overlay** (the BASIC text console). A sprite
  with its own priority bit set also goes behind every background pixel that
  isn't color 0. `LAYER_ENABLE` bits turn each layer on or off; `VIDEO_MODE`
  turns the whole picture on or off.
- **Background** is a scrollable playfield built from up to eight raw 40×25
  tile tables (nametable + attribute byte per cell). `BGMODE` picks how those
  tables tile together into one canvas (1×, 2×, or 4× the 320×200 viewport,
  horizontally, vertically, or both); `BGSET` swaps to a second complete set of
  tables (index +4) for flicker-free map swaps; `SCROLL` pans the fixed
  320×200 viewport across that canvas, wrapping at its edges.
- **Sprites** are OAM entries (tile, X, Y, palette, flip, priority, enable),
  positioned independently and clipped at the screen edge. Higher OAM indexes
  draw over lower ones.
- **CHR banks** hold tile/glyph graphics: 8 banks, each either 3bpp (8 colors)
  or 1bpp (2 colors, picking one of the bank's 3 planes). BG, sprites, and the
  overlay each have their own current bank (+ an alt bank for BG/overlay,
  selected per-cell by the `CHR_ALT` attribute bit).
- **Palette** is 16 banks of 8 RGB565 colors. The attribute byte's low nibble
  picks the bank; the pixel's decoded color index (0-7, or 0/1 in 1bpp mode)
  picks the color within it. Color 0 is drawn on the background and is
  transparent for sprites and the overlay.

Background cells and sprites do **not** share an attribute layout: a cell has
flip-X in bit 4, flip-Y in bit 5 and priority in bit 6, while a sprite's `attr`
byte has priority in bit 4, flip-X in bit 5 and flip-Y in bit 6. Both keep the
palette in bits 0-3. The SDK's video architecture page has both layouts and the
sprite `ext` byte.

## Layer, bank and palette statements

Direct register wrappers: parse args (`ILLEGAL QUANTITY` on out-of-range,
same as `COLOR`), write MIA's render-control page or palette RAM.

| Statement | Arguments | Effect |
| --- | --- | --- |
| `OVLON` / `OVLOFF` | — | Overlay visibility (`LAYER_ENABLE` bit 1). Preserves text, attributes, and other layer enables. |
| `BGON` / `BGOFF` | — | Background layer on/off (`LAYER_ENABLE` bit 0). |
| `SPRON` / `SPROFF` | — | Sprite layer on/off (`LAYER_ENABLE` bit 2). Per-sprite show/hide is a `SPRITE` field, not a separate statement. |
| `VIDON` / `VIDOFF` | — | Whole video output on/off (`VIDEO_MODE` bit 0). |
| `BGMODE n` | `n` 0-5 | BG viewport mode: `0` 40×25 (no scroll headroom), `1` 80×25, `2` 40×50, `3` 160×25, `4` 40×100, `5` 80×50 - cell counts for the *virtual scrollable map*, not the display resolution (always 320×200). |
| `BGSET n` | `n` 0 or 1 | Selects which of the two BG table sets the current `BGMODE` arrangement reads. |
| `SCROLL x,y` | `x,y` 0-65535 | BG layer pixel scroll. Wraps at the current mode's canvas size. |
| `BGBANK n` / `BGALT n` | `n` 0-7 | CHR bank the BG layer draws from normally / where a cell's `CHR_ALT` bit is set. |
| `OVLBANK n` / `OVLALT n` | `n` 0-7 | Primary / alternate overlay CHR bank. `ALT` on each cell selects between them. |
| `SPRBANK n` | `n` 0-7 | CHR bank sprites draw from. |
| `SPRCOUNT n` | `n` 0-255 | Highest OAM index the renderer scans each frame. |
| `CHRMODE bank,flag` | `bank` 0-7, `flag` 0/non-zero | Mark a CHR bank as 1bpp (`flag<>0`) or 3bpp (`flag=0`). |
| `CHRPLANE bg,spr,ovl` | each 0-3 | Which of a 1bpp bank's 3 planes (0-2) each layer decodes; only matters for banks `CHRMODE` marked 1bpp. `3` is accepted, and the renderer reads it as plane 0. |
| `PALETTE bank,index,r,g,b` | `bank` 0-15, `index` 0-7, `r`/`b` 0-31, `g` 0-63 | Write one palette RGB565 entry directly (palette fades/cycling at runtime). `PALREAD` and `PALLOAD` write palette RAM too, many bytes at a time. |

Boot state (`video_init`, `src/kernel/video.s`): overlay layer on, background
and sprites off; CHR banks 0/1 both 1bpp (overlay plane 0); primary/alternate overlay banks
are 0/1 and BG/sprite CHR banks default to bank 0.

`OVLBANK` and `OVLALT` select graphics; they do not load a font or change
`CHRMODE` or `CHRPLANE`. Any CHR bank can serve any layer, and changing a
bank's decoding mode affects every layer using it. Invalid bank numbers are
rejected before the register is changed.

`OVLOFF` hides the entire console, including prompts and the cursor. Console
output still updates the hidden overlay. `OVLON` displays its current contents
again; returning to READY does not automatically enable it. The overlay stays
fixed at 40×25 cells regardless of background scrolling.

```basic
10 OVLOFF
20 PRINT "THIS TEXT IS HIDDEN"
30 OVLON
```

Use `OVLBANK 0:OVLALT 1` to restore the default bank selections. Existing
`COLOR`, `FLIPX`, `FLIPY`, and `ALT` continue to control per-cell attributes.

## Tables, sprites and `DATA` loads

The `*READ` statements read their bytes from `DATA` items, sharing the `DATA`
pointer with `READ`: they continue where the last `READ` or `*READ` stopped,
and running out raises `?OUT OF DATA`. They are much faster than a
`FOR...READ...POKE...NEXT` loop. They borrow a variable named `Z9` (its value
is saved and restored), so `Z9` shows up among a program's variables after the
first one runs.

| Statement | Arguments | Effect |
| --- | --- | --- |
| `BGCHAR col,row,tile,attr` | `col`/`row` map-relative for the current `BGMODE` (e.g. 0-159/0-24 in mode 3) | Write one BG nametable+attribute cell in the current mode and set (see below). Out-of-range `col`/`row` raises `ILLEGAL QUANTITY` rather than wrapping. |
| `NTREAD table,cell,count` | `table` 0-7, `cell` 0-999, `count` 0-65535 | Bulk-load `count` raw nametable (tile) bytes from `DATA` into raw BG table `table`, starting at `cell`. |
| `ATRREAD table,cell,count` | same ranges as `NTREAD` | As `NTREAD`, but the attribute half of the table - a separate call over its own run of `DATA` values. |
| `CHRREAD bank,offset,count` | `bank` 0-7, `offset` 0-6143, `count` 0-65535 | Bulk-load `count` raw tile/graphics bytes from `DATA` into CHR bank `bank`. |
| `PALREAD bank,offset,count` | `bank` 0-15, `offset` 0-15, `count` 0-255 | Bulk-load `count` raw palette bytes from `DATA`, starting `offset` bytes into bank `bank`. |
| `OAMREAD n,count` | `n` 0-255, `count` 0-255 | Bulk-load `count` sprites' raw 5-byte records (`tile,xlo,ylo,attr,ext`) from `DATA`, starting at OAM index `n`. |
| `SPRITE n,tile,x,y,pal,flags` | `n`/`tile` 0-255, `x` -512..511, `y` -256..255, `pal` 0-15, `flags` bit0 disable/bit1 priority/bit2 flip-X/bit3 flip-Y | Full per-sprite setup in one call. |
| `SPRX n,x` / `SPRY n,y` | same ranges as `SPRITE`'s `x`/`y` | Change one sprite's position only - cheap per-frame animation update without respecifying every `SPRITE` field. |
| `SPRTILE n,t` | `t` 0-255 | Change one sprite's tile/frame index only. |
| `SPRCOLOR n,pal` | `pal` 0-15 | Change one sprite's palette only. |
| `SPRFLIP n,fx,fy` | each 0/non-zero | Change one sprite's flip-X/flip-Y only. |
| `SPRPRI n,p` | 0/non-zero | Change one sprite's priority only. |

### From files

These take the path first, then where, then (saves only) how many. Loads take
the whole file, and a long file runs on into the next table or bank. A cell,
offset or index left out is 0. A save's count left out means the rest of the
table, bank or sprite list from that point. An argument out of range raises
`ILLEGAL QUANTITY`, and an extra one `SYNTAX ERROR`, before any file is read
or written. File errors raise `FILE I/O ERROR` (docs/basic-file.md).

| Statement | Arguments | Effect |
| --- | --- | --- |
| `NTLOAD "file",table[,cell]` | `table` 0-7, `cell` 0-999 | Load a file into raw BG table `table`'s nametable (tile bytes) from `cell` on. |
| `ATRLOAD "file",table[,cell]` | same | Load a file into a table's attribute plane. |
| `CHRLOAD "file",bank[,offset]` | `bank` 0-7, `offset` 0-6143 | Load a file into CHR bank `bank` from byte `offset` on. |
| `PALLOAD "file",bank[,offset]` | `bank` 0-15, `offset` 0-15 | Load raw RGB565 bytes into palette RAM, palette bank `bank` from byte `offset` on. |
| `OAMLOAD "file"[,n]` | `n` 0-255 | Load 5-byte sprite records (`tile,xlo,ylo,attr,ext`) into OAM from sprite `n` on. |
| `NTSAVE "file",table[,cell[,count]]` | as `NTLOAD`, `count` 0-65535 bytes | Save `count` tile bytes, or the rest of the 1000-cell table. |
| `ATRSAVE "file",table[,cell[,count]]` | same | Save `count` attribute bytes, or the rest of the table. |
| `CHRSAVE "file",bank[,offset[,count]]` | as `CHRLOAD`, `count` 0-65535 bytes | Save `count` bytes, or the rest of the 6144-byte bank. |
| `PALSAVE "file",bank[,offset[,count]]` | as `PALLOAD`, `count` 0-65535 bytes | Save `count` palette bytes, or the rest of the 16-byte bank. |
| `OAMSAVE "file"[,n[,count]]` | as `OAMLOAD`, `count` 0-255 sprites | Save `count` sprite records, or the rest of the 256. |

```basic
10 CHRLOAD "TILES.CHR",2          ' the whole file into CHR bank 2 and on
20 PALLOAD "GAME.PAL",0           ' palette banks 0 and up
30 NTLOAD "LEVEL1.NT",0           ' table 0, from cell 0
40 CHRSAVE "BANK2.CHR",2          ' all 6144 bytes of bank 2
50 OAMSAVE "SPR.OAM",0,8          ' sprites 0-7, 40 bytes
```

### Which table a `BGCHAR` cell lands in

`BGCHAR` does the renderer's mapping (`bgTableAndLocal`) in reverse. It checks
`col` and `row` against the current mode's canvas, finds the raw table and the
cell inside it (`row MOD 25` × 40 + `col MOD 40`), adds 4 to the table when
`BGSET 1` is active, and writes the tile and attribute there, as `NTREAD` and
`ATRREAD` would for one cell. The tables each mode uses, in set 0:

| `BGMODE` | Canvas (cells) | Tables, as laid out on the canvas |
| --- | --- | --- |
| 0 | 40×25 | 0 |
| 1 | 80×25 | 0 1 |
| 2 | 40×50 | 0 above 2 |
| 3 | 160×25 | 0 1 2 3 |
| 4 | 40×100 | 0, 1, 2, 3 from top to bottom |
| 5 | 80×50 | 0 1 above 2 3 |

## Overlay regression tests

Run `python3 tests/run_input.py --run 'TestBasicOverlay|TestBasicVideo'` to
boot the freshly built ROM in the sibling emulator and check overlay controls
alongside existing video operations. The runner uses a source overlay and does
not install the image.

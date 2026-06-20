# Mapping the Clementina

A location-by-location map of the Clementina 6502 address space, in the spirit
of *Mapping the Commodore 64*. This is a **living document**: as the kernel,
BASIC port, and architecture evolve, add and revise entries here so there is a
single authoritative description of what every meaningful address does.

- Source of truth for hardware decoding: the Go emulator
  (`clementina-6502`, `pkg/computers/clementina`) and the MIA firmware
  (`clementina-mia`).
- Source of truth for kernel symbols: [`src/kernel/kernel.inc`](../src/kernel/kernel.inc).
  Keep the two in sync — if you change an address in one, change it here.

Numbers are hexadecimal unless noted. "MIA RAM" means the 256 KiB internal to
MIA, reached only through the indexed windows — it is **not** in the 6502
address space.

---

## 1. The big picture

The 65C02 sees 64 KiB. Decoding (from the Clementina CS logic):

| Range | Size | Region | Notes |
| --- | --- | --- | --- |
| `$0000–$7FFF` | 32 KiB | **Base RAM** | Flat, always present. Holds zero page, stack, the kernel image, and BASIC's workspace. |
| `$8000–$BFFF` | 16 KiB window | **Extended RAM** | A 16 KiB window into 512 KiB of banked RAM. Bank selected by VIA Port A (PA0–PA4 → 32 banks). |
| `$C000–$DFFF` | 8 KiB | **I/O** | 8 device slots of 1 KiB each. The 65C22 VIA is in slot 0 (`$C000–$C3FF`). |
| `$E000–$FFFF` | 8 KiB | **MIA region** | Pico-served. High RAM (banked 8 KiB windows, "if enabled by Pico") plus the MIA register block at `$FFE0–$FFFF`. Treat `$E000–$FFDF` as not-yet-guaranteed. |

CPU: **65C02S** (the `STZ`, `BRA`, `PHX/PLX`, etc. extensions are available).

### Base RAM detail (`$0000–$7FFF`)

| Range | Use |
| --- | --- |
| `$0000–$00FF` | Zero page (shared by kernel / BASIC / WozMon — §2) |
| `$0100–$01FF` | CPU stack (§3) |
| `$0200–$02FF` | Line input buffer (§4) |
| `$0300–$03FF` | Kernel variables and vectors (§5) |
| `$0400–…` | Kernel image: jump table (§6), then code and data (§7) |
| `…–$7FFF` | BASIC free workspace (§8) — the bytes BASIC reports as "free" |

The image is packed at the bottom so all occupied RAM is contiguous and the
free workspace is one block at the top of base RAM.

---

## 2. Zero page (`$0000–$00FF`)

Zero page is a shared, contended resource. The plan:

- **BASIC** owns the low and middle zero page. Its layout is set by
  `ZP_START1..4` and `STACK_TOP` in `src/basic/defines_clementina.s` and laid
  out in `src/basic/zeropage.s`. In practice BASIC uses roughly `$00–$DF`.
- **The kernel** keeps a small block high, `$00F0–$00FB`, so it never collides
  with BASIC. The kernel uses very little zero page because its I/O is done
  through absolute MIA registers.
- **WozMon** uses `$24–$2B`, which overlaps BASIC's area. That is fine because
  WozMon and BASIC are not active at the same time; entering one re-initializes
  what it needs.

### Kernel zero page (`$00F0–$00FB`)

Defined in the `ZEROPAGE` segment of [`src/kernel/kernel.s`](../src/kernel/kernel.s).

| Addr | Name | Size | Description |
| --- | --- | --- | --- |
| `$F0` | `KPTR` | 2 | General 16-bit pointer. Used by `PRSTR` as the string source. Not touched by `cursor_to_idxa`, so it survives a `PRSTR → CHROUT` call chain. |
| `$F2` | `KTMP` | 2 | Scratch. Holds the computed overlay offset `P = CURSOR_Y*40 + CURSOR_X`, then the 24-bit overlay address low/mid. |
| `$F4` | `KCNT` | 2 | 16-bit loop counter for screen fills. |
| `$F6` | `KCHR` | 1 | Scratch copy of the byte passed to `CHROUT`, so the routine can preserve A/X/Y while still repositioning MIA indexes. |
| `$F7–$FB` | — | 5 | Reserved for the kernel. |

> Allocation rule: BASIC must not extend past `$EF`; the kernel must not use
> below `$F0`. If BASIC needs more, shrink the kernel block, not the other way.

---

## 3. CPU stack (`$0100–$01FF`)

Standard 6502 hardware stack. `COLDSTART` sets `S = $FF`. BASIC's
`STACK_TOP` reserves the top of the stack for its FOR/GOSUB bookkeeping.

---

## 4. Line input buffer (`$0200–$02FF`)

WozMon's line buffer (`IN = $0200`). BASIC currently keeps its own input buffer
in zero page (the proven 65C02 layout — moving it here triggers an illegal
`STY abs,X` in the generic BASIC source). The two monitors are never active at
the same time.

> Open item: optionally move BASIC's input buffer to `$0200` during full BASIC
> bring-up so there is a single shared line buffer (needs the Apple/CBM-style
> non-zero-page-buffer code path).

---

## 5. Kernel variables and vectors (`$0300–$03FF`)

The kernel's permanent RAM page (analogous to the C64's `$0300` page). Defined
as `KVARS` in [`src/kernel/kernel.inc`](../src/kernel/kernel.inc).

| Addr | Name | Size | Description |
| --- | --- | --- | --- |
| `$0300` | `CURSOR_X` | 1 | Text cursor column, `0..39`. |
| `$0301` | `CURSOR_Y` | 1 | Text cursor row, `0..24`. |
| `$0302` | `TEXT_ATTR` | 1 | Overlay text attribute for new console cells. Bits `0-3` select the palette bank; the default is palette `0` white text over the blue backdrop. |
| `$0303` | `LAST_KEY` | 1 | Debug: last byte returned by `CHRIN`. Watch this in the emulator's memory window to confirm input before attaching a video client. |
| `$0304` | `KEY_COUNT` | 1 | Debug: running count of bytes read by `CHRIN`. |
| `$0305` | `CINV` | 2 | Reserved: redirectable `CHRIN` vector (not yet used). |
| `$0307` | `COUTV` | 2 | Reserved: redirectable `CHROUT` vector (not yet used). |
| `$0309` | `CURSOR_VISIBLE` | 1 | Nonzero when the software cursor glyph is currently drawn into the overlay. |
| `$030A` | `CURSOR_SAVE_CHR` | 1 | Saved tile under the visible cursor. |
| `$030B` | `CURSOR_SAVE_ATTR` | 1 | Saved attribute under the visible cursor. |
| `$030C–$0324` | `LINE_LINK` | 25 | Logical-line link table, one byte per screen row. Bit 7 set = row starts a logical line; clear = it continues the row above (line wrap). The screen editor harvests the whole logical line under the cursor on RETURN. Maintained by `clrscr`/`CHROUT`/`scroll_up`. |
| `$0325–$0374` | `EDIT_BUF` | 80 | Screen editor: the harvested logical line, doled to BASIC line input by `KERN_EDITKEY`. |
| `$0375` | `EDIT_LEN` | 1 | Harvested length (trailing spaces trimmed). |
| `$0376` | `EDIT_IDX` | 1 | Dole-out read index into `EDIT_BUF`. |
| `$0377` | `EDIT_STATE` | 1 | `0` = editor idle; nonzero = doling a harvested line. |
| `$0378` | `EDIT_START_X` | 1 | Cursor column where the current input began (past any prompt). |
| `$0379` | `EDIT_START_Y` | 1 | Cursor row where the current input began. |
| `$037A` | `EDIT_RS` | 1 | Harvest / shift scratch: logical-line start row. |
| `$037B` | `EDIT_RE` | 1 | Harvest / shift scratch: logical-line end row. |
| `$037C` | `EDIT_CP` | 1 | Insert/delete scratch: cursor position within the logical line. |
| `$037D` | `EDIT_LL` | 1 | Insert/delete scratch: logical-line cell count (capped at two rows). |
| `$037E` | `CURSOR_BLINK_ACTIVE` | 1 | Nonzero while `CHRIN` is polling and the Timer 1 IRQ handler may toggle the software cursor. |
| `$037F` | `CURSOR_BLINK_COUNT` | 1 | VIA Timer 1 ticks remaining before the next cursor toggle. |
| `$0380–$03FF` | — | | Free for future kernel state. |

---

## 6. Kernel jump table (`$0400–$0426`)

The **stable ABI**. Each entry is a 3-byte `JMP`. Callers (BASIC, WozMon, user
programs) bind to these fixed addresses; the routines behind them may move
freely. Anchored at the load base so `$0400` is also the reset entry.

| Addr | Symbol | In | Out | Description |
| --- | --- | --- | --- | --- |
| `$0400` | `KERN_COLDSTART` | — | — | Reset entry. MIA points RESET here. Sets up the machine, console, prints the banner, then enters BASIC. |
| `$0403` | `KERN_WARMSTART` | — | — | Re-enter BASIC. |
| `$0406` | `KERN_CHROUT` | `A`=char | A/X/Y preserved | Write one character to the console at the cursor. Handles CR (`$0D`, newline), LF (`$0A`, ignored), BS (`$08`), FF (`$0C`, clear), the cursor moves (`$11`/`$91`/`$1D`/`$9D`) and HOME (`$13`), printable bytes. |
| `$0409` | `KERN_CHRIN` | — | `A`=char | Blocking read of one raw text byte from the MIA FIFO (single key; used by BASIC `GET`). Updates `LAST_KEY`/`KEY_COUNT`. |
| `$040C` | `KERN_GETKEY_NB` | — | `C`=1 & `A`=char, or `C`=0 | Non-blocking read. |
| `$040F` | `KERN_STOP` | — | `Z`=1 if break | ISCNTC / Ctrl-C check. **Placeholder** today (never reports a break); real handling lands with BASIC. |
| `$0412` | `KERN_CLRSCR` | — | — | Clear the overlay (fill with spaces) and home the cursor. |
| `$0415` | `KERN_PRHEX` | `A`=nibble | — | Print the low nibble of `A` as one hex digit via `CHROUT`. |
| `$0418` | `KERN_PRBYTE` | `A`=byte | — | Print `A` as two hex digits. |
| `$041B` | `KERN_PRSTR` | `KPTR`→str | — | Print the `$00`-terminated string at `KPTR` (max 255 bytes). |
| `$041E` | `KERN_LOAD` | — | — | Storage load. **Stub** (`RTS`) until the FAT layer lands. |
| `$0421` | `KERN_SAVE` | — | — | Storage save. **Stub** (`RTS`). |
| `$0424` | `KERN_EDITKEY` | — | `A`=char | Full-screen line editor. Runs the interactive editor (cursor moves, overtype, gap-closing backspace `$08` / delete `$7F`, insert `$94`) on the overlay, harvests the logical line under the cursor on RETURN, and returns it one byte at a time ending in CR. BASIC's `GETLN` uses this for line input; `GET` stays on `KERN_CHRIN`. |

> When you add a kernel call, append a new `JMP` to the table in
> `src/kernel/kernel.s`, add the `KERN_*` equate in `kernel.inc`, bump the
> `.assert` guarding the table size, and document the new row here. Never
> reorder existing entries — that breaks the ABI.

---

## 7. Kernel code and data (`$0427–…`)

Internal routines (`CODE` segment) and read-only data (`RODATA`). These
addresses are **not** ABI; reach them only through the jump table. The current
combined kernel+BASIC image is ~9.2 KiB. Notable internal routines:

- `video_init` — load startup palettes, select MIA CHR bank `0` for the
  overlay, mark bank `0` as 1bpp, set the blue backdrop, enable video output
  and the overlay layer, then force a full refresh.
- `video_load_palettes` — load palette banks `0-7`; palette `0` is the default
  blue/white console palette and the others provide convenient text colors.
- `cursor_to_idxa` — bind the overlay index `$B8` to window A and set its
  current address (via CFG) to the cell for `CURSOR_X/Y`.
- `cursor_attr_to_idxa` — bind the overlay attribute index `$B9` to window A
  and set its current address to the current console cell.
- `cursor_show` / `cursor_hide` / `cursor_toggle` — draw, restore, or flip the
  software cursor at the current console cell while preserving the tile and
  attribute underneath it.
- `char_to_tile` — convert ASCII-ish kernel strings/input into the
  C64-style screen codes used by the default PETSCII font bank.
- `set_idxa_addr` / `set_idxa_limit` — write the current/limit address of the
  index selected in window A through the CFG registers.
- `newline` / `scroll_up` — row advance and DMA-assisted scroll: kernel-reserved
  indexes `$F0-$F3` copy the overlay nametable and attributes up by one row,
  then the last row is blanked through `$B8/$B9`.
- `via_init` — initialize the 65C22 VIA: Port A selects external RAM bank 0,
  and Timer 1 free-runs as the kernel cursor blink tick.
- `irq_handler` / `nmi_handler` — `irq_handler` read-clears MIA `IRQ_STATUS_L`,
  dispatches VIA Timer 1 ticks, and toggles the cursor only while `CHRIN` is
  polling for input.

---

## 8. BASIC free workspace (`end-of-image … $7FFF`)

At runtime BASIC's program text, variables, arrays, and strings live between
`TXTTAB` and `MEMSIZ`. Clementina currently sets `RAMSTART2 = $3000`, safely
above the combined kernel+BASIC image, and caps `MEMSIZ` at `$8000` (the start
of the banked Extended RAM window). The resulting span is what BASIC prints as
**"bytes free"**.

---

## 9. Extended RAM (`$8000–$BFFF`)

A 16 KiB window into 512 KiB of banked RAM. The active 16 KiB bank is selected
by VIA Port A bits PA0–PA4 (32 banks). Reserved for future use: RAM disk,
paged data/assets, large buffers. Not used by the kernel yet.

---

## 10. I/O (`$C000–$DFFF`)

Eight 1 KiB device slots decoded from this 8 KiB region.

| Range | Slot | Device |
| --- | --- | --- |
| `$C000–$C3FF` | 0 | **65C22 VIA**. Port A drives Extended RAM banking; Port B is free. Registers repeat every 16 bytes within the slot. Timer 1 is configured by the kernel as a free-running IRQ source for cursor blink. |
| `$C400–$DFFF` | 1–7 | Free I/O slots. |

> Hardware note: the W65C22S IRQB pin is a totem-pole output, not an
> open-drain output. Sharing `IRQB` with MIA needs external isolation or a MIA
> idle state that releases the line, not a strong high output.

---

## 11. MIA region (`$E000–$FFFF`)

MIA (the Raspberry Pi Pico 2 W interface adapter) owns this region. Today only
the register block at the very top is defined; treat `$E000–$FFDF` as reserved
("high RAM, if enabled by Pico") and do not rely on it.

### MIA register block (`$FFE0–$FFFF`)

All 32 registers, mirrored in [`src/kernel/kernel.inc`](../src/kernel/kernel.inc).

| Addr | Name | Description |
| --- | --- | --- |
| `$FFE0` | `IDXA_PORT` | Index window A data port. Read/write the byte at index A's current address; the index then steps per its flags. |
| `$FFE1` | `IDXA_SELECT` | Select which of 256 index descriptors is bound to window A. Writing also preloads `IDXA_PORT`. |
| `$FFE2` | `CFG_SELECT` | Select a configuration field. Writing loads its value into `CFG_PORT`. Field ids `$00-$0F` act on the index selected in window A, `$10-$1F` on window B's, `$20-$22` on PHI2 speed. |
| `$FFE3` | `CFG_PORT` | Configuration data port for the selected field. Writing a current-address byte refreshes that window's data port from the new address, so reads after repositioning need no re-select. |
| `$FFE4` | `IDXB_PORT` | Index window B data port. |
| `$FFE5` | `IDXB_SELECT` | Select the descriptor bound to window B. |
| `$FFE6` | `CMD_PARAM1` | Command parameter 1. |
| `$FFE7` | `CMD_PARAM2` | Command parameter 2. |
| `$FFE8` | `CMD_PARAM3` | Command parameter 3. |
| `$FFE9` | `CMD_TRIGGER` | Write a command id to queue `[id, p1, p2, p3]`. |
| `$FFEA` | `STATUS_L` | MIA status, low byte. |
| `$FFEB` | `STATUS_H` | MIA status, high byte. |
| `$FFEC` | `ERROR_L` | Read-to-pop error queue (`$00` = none). |
| `$FFED` | `ERROR_H` | Error high byte (unused). |
| `$FFEE` | `IRQ_MASK_L` | IRQ mask, low byte. |
| `$FFEF` | `IRQ_MASK_H` | IRQ mask, high byte. |
| `$FFF0` | `IRQ_STATUS_L` | Pending IRQ flags, low byte. **Read-to-clear**: reading clears all IRQ_STATUS bits and deasserts IRQ. |
| `$FFF1` | `IRQ_STATUS_H` | Pending IRQ flags, high byte. Passive read — sample this before `$FFF0` if you need high-byte flags. Bit 15 = aggregate `IRQ_TRIGGERED`. |
| `$FFF2` | `INPUT_STATUS` | Text availability, held-input summaries, active source. Bit 0 = `INPUT_STATUS_TEXT_READY`. |
| `$FFF3` | `INPUT_CHAR` | Read-to-pop text FIFO. Returns `$00` when empty. PETSCII-compatible bytes. |
| `$FFF4` | `INPUT_CHAR_COUNT` | Number of bytes queued in the text FIFO. |
| `$FFF5–$FFF9` | reserved | Read as zero. |
| `$FFFA` | `NMI_VEC` (L) | 6502 NMI vector low. **MIA-backed** — the kernel writes its handler here. |
| `$FFFB` | `NMI_VEC` (H) | 6502 NMI vector high. |
| `$FFFC` | `RESET_VEC` (L) | 6502 RESET vector low. MIA sets this to the load base after loading the kernel. |
| `$FFFD` | `RESET_VEC` (H) | 6502 RESET vector high. |
| `$FFFE` | `IRQ_VEC` (L) | 6502 IRQ/BRK vector low. Kernel writes its handler here. |
| `$FFFF` | `IRQ_VEC` (H) | 6502 IRQ/BRK vector high. |

> The reset/NMI/IRQ vectors live **inside** the MIA register block, so they are
> writable registers, not ROM. The kernel installs real handlers into
> `$FFFA/$FFFE` during `COLDSTART` before enabling interrupts.

---

## 12. MIA indexed RAM (used by the kernel)

MIA RAM is reached only through index descriptors. The kernel currently touches:

| Index | Purpose | MIA RAM target |
| --- | --- | --- |
| `$90-$97` (`VIDX_PALETTE_0-7`) | Startup palette upload | palette banks `0-7` |
| `$85` (`VIDX_BANK_SELECT`) | Select CHR bank `0` for bg/overlay/sprite consumers | render control `$28-$2C` |
| `$86` (`VIDX_CHR_1BPP`) | Mark CHR bank `0` as 1bpp and use overlay plane `1` | render control `$2D-$2E` |
| `$87` (`VIDX_BACKDROP_COLOR`) | Select palette `0`, color `0` as the blue backdrop | render control `$2F` |
| `$81` (`VIDX_LAYER_ENABLE`) | Enable the overlay layer | render control `$21` |
| `$B8` (`VIDX_OVERLAY_NT`) | Console **write cursor**: bound to window A; positioned per `CURSOR_X/Y` via CFG | overlay nametable cell |
| `$B9` (`VIDX_OVERLAY_ATTR`) | Console **attribute cursor**: bound to window A after each tile write | overlay attribute cell |
| `$F0` (`KIDX_SCROLL_NT_SRC`) | Kernel-reserved scroll DMA source | overlay nametable + 40, limit = overlay nametable end |
| `$F1` (`KIDX_SCROLL_NT_DST`) | Kernel-reserved scroll DMA destination | overlay nametable base |
| `$F2` (`KIDX_SCROLL_ATTR_SRC`) | Kernel-reserved scroll DMA source | overlay attributes + 40, limit = overlay attributes end |
| `$F3` (`KIDX_SCROLL_ATTR_DST`) | Kernel-reserved scroll DMA destination | overlay attributes base |

Index descriptors `$F0-$FF` are reserved for kernel/system use. User programs
that call kernel services should not change them.

### Overlay text layer

The console is the MIA overlay layer: a fixed **40×25** screen-space grid of
tile indices in MIA RAM at `$10080` (1000 bytes), with matching attributes at
`$10468` (1000 bytes), rendered by the remote video client. The kernel converts
printable ASCII-ish bytes to the screen-code tile indices used by MIA's default
PETSCII font bank before writing the nametable.

CFG now configures whichever index a window has selected (firmware fix), so the
console drives the overlay index `$B8` directly: it binds `$B8` to window A and
sets its current address (via the window-A CFG fields) to the cursor cell before
each write. Cold start also initializes fixed kernel scroll indexes `$F0-$F3`;
`scroll_up` uses `CMD_COPY_INDEXES` with byte count `0` to copy each source
range up to its source limit without moving the indexes.

Cold start loads a blue/white default palette, sets the backdrop to palette `0`
color `0`, sets `TEXT_ATTR = 0` so new text uses palette `0` color `1` (white),
selects CHR bank `0` for the overlay, and sets bit `0` in `CHR_1BPP_MASK` so
the default PETSCII charset is decoded as 1bpp instead of 3bpp. The overlay uses
plane `1`, the lowercase/uppercase PETSCII set; lowercase ASCII `a-z` is
converted to screen codes `1-26`, while uppercase, digits, punctuation, and
space are written unchanged.

---

## 13. Boot sequence

1. MIA powers up in **loader mode**: it writes a tiny self-modifying loader
   into the register block and points RESET at `$FFE0`.
2. The loader streams `kernel.bin` into base RAM at the **load base (`$0400`)**.
3. MIA switches to **normal mode**: it restores the normal register block and
   sets `RESET_VEC` (and defaults `NMI_VEC`/`IRQ_VEC`) to the load base.
4. The 6502 is released from reset and jumps to `$0400` → `KERN_COLDSTART`.
5. `COLDSTART` installs real NMI/IRQ handlers into `$FFFA/$FFFE`, initializes
   the console, clears the screen, prints the banner, and enters the loop.

> The load base is the constant `kernel_target_address`, set to `0x0400` in
> both the firmware (`clementina-mia` `src/mia/sys/mia.c`) and the emulator
> (`clementina-6502` `pkg/components/mia/registers.go`). Changing where this
> image boots requires updating that constant in **both** repos and
> rebuilding/embedding `kernel.bin`.

---

## 14. Conventions and how to extend this document

- One section per region; within a section, a table of named locations.
- When you add kernel state, give it a name in `kernel.inc`, place it in the
  `$0300` page (persistent) or the kernel zero-page block (hot/pointer), and
  add a row here.
- When you add a kernel call, follow the rule in §6 and document the row.
- Keep "open items" inline as block quotes so they are easy to find and clear.
- Prefer absolute, concrete addresses over "somewhere around" once a thing is
  pinned down by the build.

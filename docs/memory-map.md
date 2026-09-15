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
| `$0400–$04B6` | Free working RAM (formerly the background-`PLAY` control block) + `DIR_NAME_BUF` (§7.5) |
| `$04B7–…` | Kernel+WozMon+BASIC image (§6, §7), starting exactly at `$04B7` |
| `…–$BFFF` | BASIC's free workspace / heap (§8), filling everything above the image |

**2026-09-14 bottom-anchor rework** (reversing the 2026-09-13 top-anchored/
descending-loader design described in older commits): the image is anchored
to a fixed **low** start, `$04B7` (right after working RAM), and grows
upward — **KERNEL → WOZMON → BASIC**, in that order, so the jump table (§6)
always starts exactly at `$04B7` no matter how large the rest of the image
grows. The heap fills everything above the image, up through `$BFFF`; since
the image (kernel+WozMon+BASIC, ~23 KiB today) fits entirely below `$8000`
but the heap above it does not, BASIC's logical workspace continues into
Extended RAM bank 0 at `$8000-$BFFF` for its upper part — bank 0 must stay
selected while BASIC runs (§9). See §8 and §13 for why and how. The
rationale for anchoring this way (rather than back at the top): everything
from `$04B7` through `$BFFF` — the fixed-low `KERNEL` region (jump table +
kernel code + WozMon) excepted, which is permanently resident and never a
load target — is *reclaimable*. A loaded machine-code program that no
longer needs BASIC can overwrite BASIC's own resident region and heap
simply by loading over it (`BLOAD`, §8), the same way a C64 game overwrites
BASIC. Top-anchoring couldn't offer this: it put
~16 KiB of permanently-resident code (including the hottest routine in the
system, `CHRGET`, and the jump table itself) inside the banked Extended RAM
window, so *any* code that ever switched banks away from bank 0 risked
unmapping its own next instruction.

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
| `$F7` | `KJIFFY` | 2 | Free-running 16-bit LE tick counter, `+1` per VIA Timer 1 IRQ (≈160 Hz at 1 MHz PHI2, scales with PHI2). Wraps silently. Published in `kernel.inc`; read-only for clients. |
| `$F9–$FB` | — | 3 | Reserved for the kernel. |

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
| `$0302` | `TEXT_ATTR` | 1 | Live overlay pen for new console cells. Bits `0-3` select the palette bank; the default is palette `0` white text over the blue backdrop. BASIC output drives this transiently; the editor reasserts `EDITOR_PEN` into it whenever it takes control. |
| `$0303` | `LAST_KEY` | 1 | Debug: last byte returned by `CHRIN`. Watch this in the emulator's memory window to confirm input before attaching a video client. |
| `$0304` | `EDITOR_PEN` | 1 | Persistent editor pen. The pen the screen editor sets from the keyboard (ESC commands) and reasserts into `TEXT_ATTR` at each line edit, so the cursor and typed text keep their color across BASIC output (LIST, messages, styled `PRINT`). Was `KEY_COUNT` (a write-only debug counter). |
| `$0305` | `CINV` | 2 | Reserved: redirectable `CHRIN` vector (not yet used). |
| `$0307` | `COUTV` | 2 | Reserved: redirectable `CHROUT` vector (not yet used). |
| `$0309` | `CURSOR_VISIBLE` | 1 | Nonzero when the software cursor glyph is currently drawn into the overlay. |
| `$030A` | `CURSOR_SAVE_CHR` | 1 | Saved tile under the visible cursor. |
| `$030B` | `CURSOR_SAVE_ATTR` | 1 | Saved attribute under the visible cursor. |
| `$030C–$0324` | `LINE_LINK` | 25 | Logical-line link table, one byte per screen row. Bit 7 set = row starts a logical line; clear = it continues the row above (line wrap). The screen editor harvests the whole logical line under the cursor on RETURN. Maintained by `clrscr`/`CHROUT`/`scroll_up`. |
| `$0325–$0374` | `EDIT_BUF` | 80 | Screen editor: the harvested logical line, doled to BASIC line input by `KERN_EDITKEY`. |
| `$0375` | `EDIT_LEN` | 1 | Harvested length (trailing spaces trimmed). |
| `$0376` | `EDIT_IDX` | 1 | Dole-out read index into `EDIT_BUF`. |
| `$0377` | `EDIT_STATE` | 1 | `0` = editor idle; nonzero = doling a harvested line. BASIC's line input uses this to distinguish the synthetic final CR from a raw `$0D` glyph tile in `EDIT_BUF`. |
| `$0378` | `EDIT_START_X` | 1 | Cursor column where the current input began (past any prompt). |
| `$0379` | `EDIT_START_Y` | 1 | Cursor row where the current input began. |
| `$037A` | `EDIT_RS` | 1 | Harvest / shift scratch: logical-line start row. |
| `$037B` | `EDIT_RE` | 1 | Harvest / shift scratch: logical-line end row. |
| `$037C` | `EDIT_CP` | 1 | Insert/delete scratch: cursor position within the logical line. |
| `$037D` | `EDIT_LL` | 1 | Insert/delete scratch: logical-line cell count (capped at two rows). |
| `$037E` | `CURSOR_BLINK_ACTIVE` | 1 | Nonzero while `CHRIN` is polling and the Timer 1 IRQ handler may toggle the software cursor. |
| `$037F` | `CURSOR_BLINK_COUNT` | 1 | VIA Timer 1 ticks remaining before the next cursor toggle. |
| `$0380–$03CF` | `EDIT_ATTR_BUF` | 80 | Screen editor: harvested per-cell attributes, parallel to `EDIT_BUF`. BASIC copies these into styled heap strings for direct/input-buffer literals. |
| `$03D0` | `EDIT_MODE` | 1 | Phase 5 glyph mode (`0..2`), used by the editor to map typed `$20-$7E` to alternate tile ranges. |
| `$03D1` | `EDIT_PAINT` | 1 | Nonzero while Paint mode is active. |
| `$03D2` | `EDIT_CMD_PENDING` | 1 | Nonzero between `ESC` and its command key. |
| `$03D3–$03FC` | `STYLE_SIDE_BUF` | 42 | BASIC tokenizer scratch for Phase 6 styled program-literal sidecars. Captures compact literal attribute records before appending them to the stored program line. `$03D3–$03D4` are also reused as a transient LIST line-pointer save, and `$03D3–$03F0` (30 bytes) as `TRACK`'s MML-compile-time state and `BAND`/`VTAKE`/`VGIVE`'s voice-mask scratch (tokenizer and `TRACK`/`BAND`/`VTAKE`/`VGIVE` never run at the same moment). |
| `$03FD` | `BASIC_DEFAULT_ATTR` | 1 | BASIC default output attribute set by `COLOR`, `FLIPX`, `FLIPY`, and `ALT`. |
| `$03FE` | `BASIC_STYLE_MASK` | 1 | BASIC style override mask set by `STYLE n`, stored in overlay-attribute bit form (`$0F`, `$10`, `$20`, `$80`). |
| `$03FF` | `STYLE_BASE_LEN` | 1 | BASIC tokenizer scratch: tokenized line length before any style sidecar is appended. |

---

## 6. Kernel jump table (`$04B7–$04E6`)

The **stable ABI**. Each entry is a 3-byte `JMP`. Callers (BASIC, WozMon, user
programs) bind to these fixed addresses; the routines behind them may move
freely.

> **2026-09-14 bottom-anchor rework**: the jump table is placed **first** in
> `clementina.cfg`'s `SEGMENTS` list, so it lands on the bottom 48 bytes of
> the image — always `$04B7-$04E6`, right after working RAM — no matter how
> large the rest of the image grows. `KERN_BASE` (`kernel.inc`) is the plain
> fixed constant `$04B7`, a true compile-time constant that never needs
> bumping. See §8 and §13 for the full picture and the single-pass build
> that makes this work.

| Addr | Symbol | In | Out | Description |
| --- | --- | --- | --- | --- |
| `$04B7` | `KERN_COLDSTART` | — | — | Reset entry. MIA points RESET here. Sets up the machine, console, prints the banner, then enters BASIC. |
| `$04BA` | `KERN_WARMSTART` | — | — | Re-enter BASIC at the READY prompt, **preserving** the current program and variables. Resets the stack and re-enables interrupts first, so it is safe to reach mid-statement (used by WozMon's `Q` quit command; `BFD3R`-style manual re-entry still works). |
| `$04BD` | `KERN_CHROUT` | `A`=char | A/X/Y preserved | Write one character to the console at the cursor. Handles CR (`$0D`, newline), LF (`$0A`, ignored), BS (`$08`), FF (`$0C`, clear), the cursor moves (`$11`/`$91`/`$1D`/`$9D`) and HOME (`$13`), printable bytes. |
| `$04C0` | `KERN_CHRIN` | — | `A`=char | Blocking read of one raw text byte from the MIA FIFO (single key; used by BASIC `GET`). Shows the cursor while waiting and updates `LAST_KEY`. |
| `$04C3` | `KERN_GETKEY_NB` | — | `C`=1 & `A`=char, or `C`=0 | Non-blocking read. |
| `$04C6` | `KERN_STOP` | — | `Z`=1 if break | ISCNTC / Ctrl-C check. **Placeholder** today (never reports a break); real handling lands with BASIC. |
| `$04C9` | `KERN_CLRSCR` | — | — | Clear the overlay (fill with spaces) and home the cursor. |
| `$04CC` | `KERN_PRHEX` | `A`=nibble | — | Print the low nibble of `A` as one hex digit via `CHROUT`. |
| `$04CF` | `KERN_PRBYTE` | `A`=byte | — | Print `A` as two hex digits. |
| `$04D2` | `KERN_PRSTR` | `KPTR`→str | — | Print the `$00`-terminated string at `KPTR` (max 255 bytes). |
| `$04D5` | `KERN_LOAD` | `KPTR`=dest override or 0, `KTMP`=run addr or 0 | — (or does not return, if run) | Stream a bank-aware PRG file straight into CPU RAM, entirely kernel-resident (see §8 and `docs/basic-file.md`) — the destination may overwrite BASIC's own resident code/heap, so it cannot call out to any BASIC-resident routine mid-copy. BASIC's `BLOAD` statement stages the path (via MIA hardware state, not CPU RAM) and parses `run`/`addr` before handing off here. |
| `$04D8` | `KERN_SAVE` | — | — | Storage save. **Stub** (`RTS`) — unlike `KERN_LOAD`, saving never overwrites running code, so `BSAVE` (`docs/basic-file.md`) is implemented entirely BASIC-resident instead and does not use this slot. |
| `$04DB` | `KERN_EDITKEY` | — | `A`=char | Full-screen line editor. Runs the interactive editor (cursor moves, overtype, gap-closing backspace `$08` / delete `$7F`, insert `$94`) on the overlay, harvests the logical line under the cursor on RETURN, and returns it one byte at a time followed by a synthetic final CR. BASIC's `GETLN` uses this for line input and treats bytes returned while `EDIT_STATE` is nonzero as raw source data; `GET` stays on `KERN_CHRIN`. |
| `$04DE` | `KERN_CHROUT_GLYPH` | `A`=tile | A/X/Y preserved | Write `A` to the console as a raw glyph at the cursor, bypassing control-code handling (so high tiles that collide with codes like `$0D` still draw). |
| `$04E1` | `KERN_WOZMON` | — | (does not return) | Enter the WOZ monitor (`src/monitor/wozmon-clementina.s`). Examine/deposit memory and run code; quit back to BASIC with `Q` (runs `KERN_WARMSTART`). Invoke from BASIC with `MON`; the older `USR` vector method still works. |
| `$04E4` | `KERN_SET_BACKDROP` | `A`=selector | — | Write the backdrop selector to `VIDX_BACKDROP_COLOR` (IRQ-safe tail call). |

> When you add a kernel call, append a new `JMP` to the table in
> `src/kernel/kernel.s`, add the `KERN_*` equate in `kernel.inc`, bump
> `KERN_JUMPTAB_SIZE` and the `.assert` guarding the table size, and document
> the new row here. Never reorder existing entries — that breaks the ABI. Also
> update the hardcoded duplicate `KERN_*` constants in `clementina_extra.s`,
> `defines_clementina.s`, and `wozmon-clementina.s` (BASIC/WozMon deliberately
> don't `.include kernel.inc`).

---

## 7. Kernel code and data (right after the jump table, from `$04E7`)

Internal routines (`KERNCODE`/`RODATA`/`WOZCODE` segments). These addresses
are **not** ABI; reach them only through the jump table. The kernel+WozMon
portion of the image is ~3.9 KiB (`$04B7`-`$1446` today); see §8 for the
combined kernel+WozMon+BASIC image size and how it's anchored. Notable
internal routines:

- `video_init` — select MIA CHR bank `0` for the overlay, mark bank `0` as 1bpp,
  set the blue backdrop, enable video output and the overlay layer, then force a
  full refresh. Startup palette RGB data is seeded by MIA firmware/emulator video
  initialization, not by the kernel.
- `cursor_to_idxa` — bind the overlay index `$B8` to window A and set its
  current address (via CFG) to the cell for `CURSOR_X/Y`.
- `cursor_attr_to_idxa` — bind the overlay attribute index `$B9` to window A
  and set its current address to the current console cell.
- `cursor_show` / `cursor_hide` / `cursor_toggle` — draw, restore, or flip the
  software cursor at the current console cell while preserving the tile and
  attribute underneath it. The cursor is an input-time construct: `chrout` hides
  it before drawing and does **not** re-show it, so it is invisible during program
  output (PRINT/LIST). `chrin` shows it (in `EDITOR_PEN`) while waiting for a key,
  and the Timer-1 IRQ blinks it — mirroring how the C64/Spectrum only cursor during
  input/editing.
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

## 7.5. `DIR_NAME_BUF` (`$048F–$04B6`) and free working RAM (`$0400–$048E`)

`$0400–$048E` (143 bytes) is fixed working RAM right after `KVARS`, currently
unused. It used to hold the background-`PLAY` control block (`BGP_*` in
`src/basic/clementina_extra.s`) — the state the Timer-1 IRQ needed to run
`PLAY s$,n`'s background sequencer independently of the foreground
interpreter. `PLAY`, its background player, and `BGP_*` were all retired
(2026-09-14): background music now runs entirely on MIA's own sequencer, so
nothing on the 6502 side needs a fixed, IRQ-safe control block for it any
more. See `docs/basic-sound.md` and `clementina-mia`'s
`docs/audio-sequencer.md`.

`DIR_NAME_BUF` (40 bytes, `$048F–$04B6`), defined as a plain equate in
`src/basic/clementina_extra.s` exactly like `KVARS`/`KJIFFY` — never part of
the loaded image, so it costs no ROM bytes — is a transient scratch buffer
`DIR` (`docs/basic-file.md`) reads one directory entry's name into before
printing any of it. It kept its address (rather than sliding down into the
freed `$0400–$048E` space) when the background-`PLAY` block was removed, so
nothing else in this fixed low-RAM region needs to move; nothing needs
`DIR_NAME_BUF` to survive between `DIR` invocations.

---

## 8. BASIC free workspace (`__BASICMEM_LAST__ … $BFFF`)

**2026-09-14 bottom-anchor rework** (reversing the 2026-09-13 top-anchored/
descending-loader design). BASIC's program text, variables, arrays, and
strings live between `TXTTAB` and `MEMSIZ`, exactly as before - what changed
is where the *image* sits relative to that heap. The loaded kernel+WozMon+
BASIC image briefly sat **above** the heap (ending exactly at `$BFFF`,
descending-loader design); it is now bottom-anchored instead, sitting
**below** the heap, starting exactly at `$04B7` (right after working RAM)
and growing upward through **KERNEL → WOZMON → BASIC** - see §13 for the
loader that makes this possible with zero wasted address space, in a single
`ld65` pass (no two-pass "measure, then relink" build needed: a fixed
*start* lets the linker place everything forward natively, unlike a fixed
*end*, which needs the start computed backward from the total size first).

Concretely: `KERNEL` (`clementina.cfg`) is a generously-sized MEMORY region
(`$04B7`, size `$1000`) holding kernel+WozMon; `BASICMEM` starts immediately
after it ends (`__KERNEL_LAST__`, ld65-defined) and holds BASIC's own
core+tables+extensions, growing up to `$C000` (immediately below I/O).
`TXTTAB` (bottom of the heap) is set directly from `__BASICMEM_LAST__`, a
symbol `clementina.cfg` exports marking wherever BASIC's own image content
actually ends; `MEMSIZ` (top of the heap) is simply the fixed hardware
boundary `$C000` - BASIC's cold-start (`init.s`) reads `__BASICMEM_LAST__`
directly instead of running the generic RAM probe upward from a low start,
since that probe writes test patterns byte-by-byte and would corrupt the
live, running image if it ever reached it (the image now sits *below* the
heap, not above it, so there's nothing to discover at runtime either way).

With the current ~23.4 KiB image (kernel+WozMon+BASIC, `$04B7`-`$62F4`
today), this gives BASIC **23,819 bytes free** (`$62F5` to `$BFFF`,
confirmed against the boot banner's own "BYTES FREE" line) - an image that
needs no manual boundary maintenance as commands are added: there is no
`MAX_KERNEL_BYTES`-style hand-maintained ceiling. `KERNEL`'s own `$1000`
region size in `clementina.cfg` is a soft ceiling only kernel+WozMon growth
can hit (`ld65` fails loudly if it ever does) - ordinary BASIC-side growth
(new statements, bigger tables) only ever eats into free heap bytes, never a
hand-maintained budget.

`clementina-6502` mirrors a piece of this in test code and needs updating
whenever addresses in this section move again: `pkg/computers/clementina/
guessing_game_test.go` (a CPU-runaway sanity check's valid-PC range) — grep
that repo for the current hex value before moving `KERN_BASE` again.

> **Known landmine — avoid `TXTTAB` in ~`[$39FE, $3AC0]`.** A pre-existing latent
> bug (present on the stock baseline, independent of the extension tokens) makes
> `INPUT` misread its buffer and re-prompt `??` when the program text begins in
> that ~200-byte window. `TXTTAB` (`__BASICMEM_LAST__`) currently sits far above
> it (`$62F5` today) and moves only as the image itself grows/shrinks, but the
> root cause is still not diagnosed - re-check this if the image's size changes
> enough to approach that window.

Bank 0 must remain selected while BASIC is active - the image itself
(kernel+WozMon+BASIC, ~23.4 KiB) fits entirely below `$8000` today, but the
**heap** above it does not: `TXTTAB`..`MEMSIZ` spans from `$62F5` up through
`$BFFF`, so its upper ~16 KiB (program text/variables/arrays/strings, once
the heap grows that far) lives in Extended RAM bank 0. Changing PA0-PA4 away
from bank 0 while BASIC is still running would therefore replace part of the
live heap out from under it; kernel warm start restores bank 0 before
returning to the interpreter, and a `BLOAD` into a *different* bank never
touches bank 0 at all (§9).

---

## 9. Extended RAM (`$8000–$BFFF`)

A 16 KiB window into 512 KiB of banked RAM. The active 16 KiB bank is
selected by VIA Port A bits PA0–PA4 (32 banks). Bank 0 holds the upper part
of BASIC's heap (§8) whenever it grows past `$8000` — it is not ordinary
free storage the way banks 1–31 are, and must be selected again before
resuming BASIC after using any other bank. Banks 1–31 are entirely free for
bank-aware access: `BLOAD`/`BSAVE`'s bank-aware PRG format (`docs/basic-file.md`)
targets them directly (bank required, 1-31; bank 0 is never a valid target -
it's the running heap), a RAM disk, paged data/assets, or large buffers.

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

**2026-09-14 bottom-anchor rework** (reversing the 2026-09-13 top-anchored/
descending-loader design): MIA's bootstrap loader writes **ascending** (from
a fixed low address, incrementing) - the classic loader direction. This is
what lets the image start exactly at `$04B7` with zero wasted space,
regardless of how large it grows: the loader's start address is always the
same fixed constant (`$04B7`), and the image's actual *end* — which does
vary release to release — is simply wherever the incrementing writes stop,
never something the firmware needs to know or recompute.

1. MIA powers up in **loader mode**: it writes a tiny self-modifying loader
   into the register block and points RESET at `$FFE0`.
2. The loader streams `kernel.bin` into base RAM **ascending from `$04B7`**:
   the first byte transmitted lands at `$04B7`, the next at `$04B8`, and so
   on, forward through `kernel_data[]` while the write target increments —
   the image ends up in the same byte order it was linked in.
3. MIA switches to **normal mode**: it restores the normal register block and
   sets `RESET_VEC` (and defaults `NMI_VEC`/`IRQ_VEC`) to `$04B7` — the fixed
   start of the jump table (§6), same as the loader's own start point.
4. The 6502 is released from reset and jumps to `$04B7` → `KERN_COLDSTART`.
5. `COLDSTART` installs real NMI/IRQ handlers into `$FFFA/$FFFE`, initializes
   the console, clears the screen, prints the banner, and enters the loop.

> Two fixed constants drive this, in both the firmware (`clementina-mia`
> `src/mia/sys/mia.c`: `kernel_load_bottom_address`/`kernel_target_address`)
> and the emulator (`clementina-6502` `pkg/components/mia/registers.go`:
> `miaKernelLoadBottomAddress`/`miaKernelTargetAddress`) — both **`$04B7`**
> (where the ascending loader starts writing, and the jump table's start /
> the RESET-NMI-IRQ vector target — the same address, since the loader
> direction now matches the jump table's own fixed position). Neither needs
> to change as the ROM image grows or shrinks — that's the whole point of
> anchoring to a fixed low start. They would only need to move together if
> the working-RAM footprint below `$04B7` itself changed (§7.5), which is
> rare and deliberate, unlike the constant churn of extension commands being
> added.

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

## MIA wall-time clock

`TI`, `TICKS(0)`, and `DELAY` use command-latched MIA timer snapshots, independently
of KJIFFY and PHI2. The snapshot occupies MIA RAM `$11078–$1107F` (not CPU RAM).
Kernel snapshot and delay scratch storage are linked into the loaded image; no
fixed workspace addresses change. See [BASIC timing](basic-timing.md).

## General MIA RAM operations

BASIC `MPEEK`, `MPOKE`, `MCOPY`, and `MFILL` address MIA RAM `$00000–$3FFFF`,
independently of CPU RAM and VIA bank selection. Kernel scratch descriptors
`$F4` and `$F5` are reserved for these operations; argument and temporary bytes
are linked into the loaded image. See [BASIC MIA memory](basic-memory.md).

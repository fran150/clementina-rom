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
address space. §12 maps it.

---

## 1. The big picture

The 65C02 sees 64 KiB. Decoding (from the Clementina CS logic):

| Range | Size | Region | Notes |
| --- | --- | --- | --- |
| `$0000–$7FFF` | 32 KiB | **Base RAM** | Flat, always present. Holds zero page, stack, the kernel image, and BASIC's workspace. |
| `$8000–$BFFF` | 16 KiB window | **Extended RAM** | A 16 KiB window into 512 KiB of banked RAM. Bank selected by VIA Port A (PA0–PA4 → 32 banks). |
| `$C000–$DFFF` | 8 KiB | **I/O** | 8 device slots of 1 KiB each. The 65C22 VIA is in slot 0 (`$C000–$C3FF`). |
| `$E000–$FFFF` | 8 KiB | **MIA region** | The 32 MIA registers at `$FFE0–$FFFF`. MIA sees only A0–A4, so `$E000–$FFDF` repeats them every 32 bytes; never use those mirrors (§11). |

CPU: **65C02S** (the `STZ`, `BRA`, `PHX/PLX`, etc. extensions are available).

### Base RAM detail (`$0000–$7FFF`)

| Range | Use |
| --- | --- |
| `$0000–$00FF` | Zero page: BASIC `$00–$97`, programs `$98–$DF`, system `$E0–$FF` (§2) |
| `$0100–$01FF` | CPU stack (§3) |
| `$0200–$02FF` | Line input buffers, BASIC's and WozMon's, free bytes for programs, and the clock snapshot (§4) |
| `$0300–$03FF` | Kernel variables and vectors (§5) |
| `$0400–$0435` | Kernel jump table (§6), the first bytes of the loaded image |
| `$0436–…` | Rest of the image: `DIR_NAME_BUF` (§7.5), kernel+WozMon (§7), then BASIC (§8) |
| `…–$BFFF` | BASIC's free workspace / heap (§8), filling everything above the image |

**2026-09-14 bottom-anchor rework** (reversing the 2026-09-13 top-anchored/
descending-loader design described in older commits): the image is anchored
to a fixed **low** start, `$0400` (right after working RAM), and grows
upward — **KERNEL → WOZMON → BASIC**, in that order, so the jump table (§6)
always starts exactly at `$0400` no matter how large the rest of the image
grows. Base RAM has no unused gap: working RAM, the image and the heap are
contiguous (§7.5 has the history). The heap fills everything above the image, up through `$BFFF`; since
the image (kernel+WozMon+BASIC, ~24 KiB today) fits entirely below `$8000`
but the heap above it does not, BASIC's logical workspace continues into
Extended RAM bank 0 at `$8000-$BFFF` for its upper part — bank 0 must stay
selected while BASIC runs (§9). See §8 and §13 for why and how. The
rationale for anchoring this way (rather than back at the top): everything
from `$0400` through `$BFFF` — the fixed-low `KERNEL` region (jump table +
kernel code + WozMon) excepted, which is permanently resident and never a
load target — is *reclaimable*. A loaded machine-code program that no
longer needs BASIC can overwrite BASIC's own resident region and heap
simply by loading over it (`BRUN`, §8), the same way a C64 game overwrites
BASIC. Top-anchoring couldn't offer this: it put
~16 KiB of permanently-resident code (including the hottest routine in the
system, `CHRGET`, and the jump table itself) inside the banked Extended RAM
window, so *any* code that ever switched banks away from bank 0 risked
unmapping its own next instruction.

---

## 2. Zero page (`$0000–$00FF`)

Zero page is split into three contiguous blocks: BASIC at the bottom, a block
free for programs in the middle, and the system (kernel and WozMon) at the
top.

| Range | Owner | Notes |
| --- | --- | --- |
| `$00–$97` | BASIC | Laid out by `ZP_START1..4` in `src/basic/defines_clementina.s` and `src/basic/zeropage.s`. Ends with the `CHRGET` routine (`$7B–$97`) that cold start copies there. |
| `$98–$DF` | Programs | 72 bytes. BASIC, WozMon and the kernel never touch them, so machine code called from BASIC (`SYS`, `USR`) can keep state here across calls. `ZP_FREE_START`/`ZP_FREE_END` in `kernel.inc`. |
| `$E0–$E7` | System | Spare. Kept next to the programs' block so it can be handed to programs later without splitting it. |
| `$E8–$EF` | WozMon | Its eight variables (`XAML` … `MODE`), used only while it runs. Outside BASIC's block, so `MON` … `Q` keeps the program and its variables. |
| `$F0–$FF` | Kernel | `$F0–$FB` used (table below), `$FC–$FF` spare. |

Rules:

- Machine code that returns to BASIC uses only `$98–$DF`. Anything else it
  borrows it must restore before returning.
- A program that replaces BASIC (loaded over it, §8) may also use `$00–$97`,
  but leaves `$E0–$FF` alone: the kernel IRQ updates `KJIFFY`, and
  `KERN_LOAD` takes its parameters in `KPTR`/`KTMP`.
- BASIC must not grow past `$97`; an `.assert` in
  `src/basic/clementina_extra.s` fails the build if it does. The kernel grows
  into its spare bytes first, then into `$E0–$E7`.

### Kernel zero page (`$00F0–$00FB`)

Defined in the `KZEROPAGE` segment of [`src/kernel/kernel.s`](../src/kernel/kernel.s),
except the `KERN_LOAD` scratch, which `src/kernel/load.s` names.

| Addr | Name | Size | Description |
| --- | --- | --- | --- |
| `$F0` | `KPTR` | 2 | General 16-bit pointer. Used by `PRSTR` as the string source. Not touched by `cursor_to_idxa`, so it survives a `PRSTR → CHROUT` call chain. `KERN_LOAD` takes its destination override here. |
| `$F2` | `KTMP` | 2 | Scratch. Holds the computed overlay offset `P = CURSOR_Y*40 + CURSOR_X`, then the 24-bit overlay address low/mid. `KERN_LOAD` takes its run address here (only when it jumps). |
| `$F4` | `KCNT` | 2 | 16-bit loop counter for screen fills. |
| `$F6` | `KCHR` | 1 | Scratch copy of the byte passed to `CHROUT`, so the routine can preserve A/X/Y while still repositioning MIA indexes. |
| `$F7` | `KJIFFY` | 2 | Free-running 16-bit LE tick counter, `+1` per VIA Timer 1 IRQ, which is once per 6250 PHI2 cycles (PHI2 ÷ 6250: 192 Hz at the 1.2 MHz default). It follows the CPU clock, so it measures CPU work, not wall time; use `TI`/`TICKS` (MIA's timer) for wall time. Wraps silently (every 65,536 ticks, ≈5.7 min at 1.2 MHz) and stops while IRQs are masked or Timer 1's IRQ is off. Read it high, low, high, and retry if the high byte changed, since the IRQ can carry between the two bytes. Published in `kernel.inc`; read-only for clients. |
| `$F9` | `KLOAD_BANK` | 1 | `KERN_LOAD`: the bank being written at `$8000-$BFFF`. |
| `$FA` | `KLOAD_CHUNKLEN` | 1 | `KERN_LOAD`: bytes read this round. |
| `$FB` | `KLOAD_SCRATCH` | 1 | `KERN_LOAD`: header and boundary scratch. |

---

## 3. CPU stack (`$0100–$01FF`)

Standard 6502 hardware stack. `COLDSTART` sets `S = $FF`. BASIC's
`STACK_TOP` reserves the top of the stack for its FOR/GOSUB bookkeeping.

While BASIC runs, its stack stays below `$01FD`: cold start sets `S = $FB`,
and `STKINI` and `BASIC_WARM_START` (the `KERN_WARMSTART` target, entered
with `S = $FF`) set `S = STACK_TOP = $FC`. The top four bytes, `$01FC–$01FF`,
sit just below BASIC's line input buffer and belong to it (§4); of those,
pushes reach only `$01FC`, a byte BASIC does not need to keep.

---

## 4. Line input buffers and clock snapshot (`$0200–$02FF`)

Both line buffers live here: WozMon's (`IN = $0200`) and BASIC's
(`INPUTBUFFER = $0200`). WozMon and BASIC are never active at the same time
(leaving WozMon with `Q` re-enters BASIC through `KERN_WARMSTART`), so they
share the page. BASIC uses msbasic's non-zero-page buffer code, the
Applesoft/Commodore BASIC 2 layout (`CONFIG_NO_INPUTBUFFER_ZP` /
`CONFIG_INPUTBUFFER_0200`, set by defining `INPUTBUFFER` in
`src/basic/defines_clementina.s`).

| Addr | Owner | Description |
| --- | --- | --- |
| `$01FC–$01FD` | BASIC | `INPUTBUFFER-4..-3`: staged link of a numbered line. `PUT_NEW_LINE` copies the stored line from `INPUTBUFFER-4`; it writes `$01` to the high byte (`$01FD`) just before the copy, since `FIX_LINKS` treats a zero high byte as the end of the program. The low byte is a don't-care that `FIX_LINKS` rewrites (§3). |
| `$01FE–$01FF` | BASIC | `INPUTBUFFER-2..-1`: staged line number, written from `LINNUM` just before the copy. `INPUT` stores its leading comma at `$01FF`. |
| `$0200–$024F` | BASIC | Up to 80 typed characters (`INLIN_MAX`, the screen editor's logical line, `EDIT_BUF_SIZE`). The tokenizer crunches the line in place, so tokenized text never runs past the typed text. `GET` uses `$0200–$0201`. |
| `$0250` | BASIC | `$00` terminator after an 80-character line. |
| `$0251–$0252` | BASIC | The tokenizer writes an end-of-program `$00` two bytes past the tokenized line's terminator (at most `$0252`), which direct-mode `NEWSTT` reads as a zero link. |
| `$0200–$027F` | WozMon | `IN`, WozMon's line buffer. |
| `$0280–$02F7` | — | Free for programs (120 bytes). Nothing in the system writes here. |
| `$02F8–$02FF` | Kernel | `CLOCK_SNAPSHOT`: the CPU copy of MIA's clock, written by `KERN_RDTIM` (below). |

`EDIT_ATTR_BUF` (§5) holds the attributes of the same cells, indexed in
parallel with `INPUTBUFFER`; at 80 bytes it covers a full line.

### Clock snapshot (`$02F8–$02FF`)

`KERN_RDTIM` (§6) asks MIA for its clock and copies the 8 bytes here, the same
layout MIA latches at `$11078` (see "MIA wall-time clock" below). The bytes
hold their values until the next `KERN_RDTIM`; they are not a live counter.
BASIC's `TI`, `TICKS` and `DELAY` read the clock the same way and overwrite
this area, so a program reads it right after its own `KERN_RDTIM`.

| Addr | Name | Size | Contents |
| --- | --- | --- | --- |
| `$02F8` | `CLOCK_MS` | 4 | Milliseconds since MIA reset, little-endian, wraps at 2^32 (about 49.7 days). |
| `$02FC` | `CLOCK_60HZ` | 3 | MIA's 60 Hz count, little-endian, wraps at 5,184,000 (24 hours). BASIC's `TI` reads this value. `KERN_SETTIM` sets it. |
| `$02FF` | `CLOCK_VERSION` | 1 | `1` when MIA filled the snapshot. |

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
| `$0305` | `KLOAD_SAVED_BANK` | 1 | `KERN_LOAD`: the bank mapped when it started, selected again when it returns or fails. |
| `$0306` | `DATA_BANK` | 1 | The bank BASIC's `BANK` statement picked for `BLOAD`, `BRUN`, `BSAVE`, `PEEK`, `POKE` and `SYS` at `$8000-$BFFF`. 0 at cold and warm start. |
| `$0307` | `KLOAD_RUN_BANK` | 1 | `KERN_LOAD`: the bank it was asked to load into, mapped again before it jumps. |
| `$0308` | `KLOAD_MODE` | 1 | `KERN_LOAD`: bit 7 set when it jumps instead of returning. |
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
| `$03D3–$03FC` | `STYLE_SIDE_BUF` | 42 | BASIC tokenizer scratch for Phase 6 styled program-literal sidecars. Captures compact literal attribute records before appending them to the stored program line. `$03D3–$03D4` are also reused as a transient LIST line-pointer save, and `$03D3–$03F8` (38 bytes) as `TRACK`'s MML-compile-time state (including its optional explicit-address parse, JUMP-delta scratch and `&` tie state) and `BAND`/`VTAKE`/`VGIVE`'s voice-mask scratch (tokenizer and `TRACK`/`BAND`/`VTAKE`/`VGIVE` never run at the same moment). |
| `$03FD` | `BASIC_DEFAULT_ATTR` | 1 | BASIC default output attribute set by `COLOR`, `FLIPX`, `FLIPY`, and `ALT`. |
| `$03FE` | `BASIC_STYLE_MASK` | 1 | BASIC style override mask set by `STYLE n`, stored in overlay-attribute bit form (`$0F`, `$10`, `$20`, `$80`). |
| `$03FF` | `STYLE_BASE_LEN` | 1 | BASIC tokenizer scratch: tokenized line length before any style sidecar is appended. |

---

## 6. Kernel jump table (`$0400–$0435`)

The **stable ABI**. Each entry is a 3-byte `JMP`. Callers (BASIC, WozMon, user
programs) bind to these fixed addresses; the routines behind them may move
freely.

> **2026-09-14 bottom-anchor rework**: the jump table is placed **first** in
> `clementina.cfg`'s `SEGMENTS` list, so it lands on the bottom 54 bytes of
> the image — always `$0400-$0435`, right after working RAM — no matter how
> large the rest of the image grows. `KERN_BASE` (`kernel.inc`) is the plain
> fixed constant `$0400`, a true compile-time constant that never needs
> bumping. See §8 and §13 for the full picture and the single-pass build
> that makes this work.

| Addr | Symbol | In | Out | Description |
| --- | --- | --- | --- | --- |
| `$0400` | `KERN_COLDSTART` | — | — | Reset entry. MIA points RESET here. Sets up the machine, console, prints the banner, then enters BASIC. |
| `$0403` | `KERN_WARMSTART` | — | — | Re-enter BASIC at the READY prompt, **preserving** the current program and variables. Resets the stack, puts the kernel's handler back in `IRQ_VEC`, and re-enables interrupts first, so it is safe to reach mid-statement (used by WozMon's `Q` quit command; `BFD3R`-style manual re-entry still works). |
| `$0406` | `KERN_CHROUT` | `A`=char | A/X/Y preserved | Write one character to the console at the cursor. Handles CR (`$0D`, newline), LF (`$0A`, ignored), BS (`$08`), FF (`$0C`, clear), the cursor moves (`$11`/`$91`/`$1D`/`$9D`) and HOME (`$13`), printable bytes. |
| `$0409` | `KERN_CHRIN` | — | `A`=char | Blocking read of one raw text byte from the MIA FIFO (single key; used by BASIC `GET`). Shows the cursor while waiting and updates `LAST_KEY`. |
| `$040C` | `KERN_GETKEY_NB` | — | `C`=1 & `A`=char, or `C`=0 | Non-blocking read. |
| `$040F` | `KERN_CLRSCR` | — | — | Clear the overlay (fill with spaces) and home the cursor. |
| `$0412` | `KERN_PRHEX` | `A`=nibble | — | Print the low nibble of `A` as one hex digit via `CHROUT`. |
| `$0415` | `KERN_PRBYTE` | `A`=byte | — | Print `A` as two hex digits. |
| `$0418` | `KERN_PRSTR` | `KPTR`→str | — | Print the `$00`-terminated string at `KPTR` (max 255 bytes). |
| `$041B` | `KERN_LOAD` | `A`=bank for `$8000-$BFFF`; `C`=0 return, 1 jump; `KPTR`=dest override or 0; `KTMP`=run addr, or 0 for the first byte loaded (jump only) | — (or does not return, with `C`=1) | Stream a PRG file (2-byte address header) straight into CPU RAM, entirely kernel-resident (see §8 and `docs/basic-file.md`) — the destination may overwrite BASIC's own resident code/heap, so it cannot call out to any BASIC-resident routine mid-copy. Any RAM below `$C000` is accepted; bytes at `$8000-$BFFF` go to bank `A`, and a load past `$BFFF` continues in the next bank. A returning load selects the bank that was mapped before; a jump maps bank `A` and enables IRQs. BASIC's `BLOAD`/`BRUN` stage the path (via MIA hardware state, not CPU RAM) and pass `DATA_BANK` in `A`. |
| `$041E` | `KERN_EDITKEY` | — | `A`=char | Full-screen line editor. Runs the interactive editor (cursor moves, overtype, gap-closing backspace `$08` / delete `$7F`, insert `$94`) on the overlay, harvests the logical line under the cursor on RETURN, and returns it one byte at a time followed by a synthetic final CR. BASIC's `GETLN` uses this for line input and treats bytes returned while `EDIT_STATE` is nonzero as raw source data; `GET` stays on `KERN_CHRIN`. |
| `$0421` | `KERN_CHROUT_GLYPH` | `A`=tile | A/X/Y preserved | Write `A` to the console as a raw glyph at the cursor, bypassing control-code handling (so high tiles that collide with codes like `$0D` still draw). |
| `$0424` | `KERN_WOZMON` | — | (does not return) | Enter the WOZ monitor (`src/monitor/wozmon-clementina.s`). Examine/deposit memory and run code; quit back to BASIC with `Q` (runs `KERN_WARMSTART`). Invoke from BASIC with `MON`; the older `USR` vector method still works. |
| `$0427` | `KERN_SET_BACKDROP` | `A`=selector | — | Write the backdrop selector to `MIA_VIDEO_INDEX_BACKDROP_COLOR` (IRQ-safe tail call). |
| `$042A` | `KERN_IRQ` | A/X/Y as at interrupt entry | (returns from the interrupt) | The kernel's IRQ handler, for chaining: a program's own handler ends with `JMP KERN_IRQ` so the kernel keeps counting `KJIFFY`, blinking the cursor and clearing MIA's IRQ status. See "Taking over the IRQ" below. |
| `$042D` | `KERN_PLOT` | `C`=1: — / `C`=0: `X`=row, `Y`=column | `C`=1: `X`=row, `Y`=column / `C`=0: `C`=0, or `C`=1 if out of range | Read or move the text cursor, with the C64's `PLOT` registers. With `C`=0 it moves the cursor to row `0..24`, column `0..39`; an out-of-range position returns `C`=1 and moves nothing. `A` is preserved. BASIC's `POS`/`TAB` column is not updated. |
| `$0430` | `KERN_RDTIM` | — | `C`=1 if valid; `A`/`X`/`Y` clobbered | Copy MIA's clock to `CLOCK_SNAPSHOT` (`$02F8–$02FF`, §4). `C`=0 means the MIA firmware has no clock. Foreground only. |
| `$0433` | `KERN_SETTIM` | `A`/`X`/`Y` = low/middle/high byte | `A`/`X`/`Y` clobbered | Set MIA's 60 Hz count (what BASIC reads as `TI`). MIA ignores values of 5,184,000 or more. Also leaves the value in `CLOCK_60HZ`. Foreground only. |

> **2026-10-11**: the `KERN_STOP` and `KERN_SAVE` stubs
> were removed and every later entry moved down 3 or 6 bytes. Neither ever did
> anything: BASIC checks Ctrl-C itself in `ISCNTC`, and `SAVE`/`BSAVE` are
> BASIC-resident wrappers around MIA's file commands, which machine code can
> issue directly.

> When you add a kernel call, append a new `JMP` to the table in
> `src/kernel/kernel.s`, add the `KERN_*` equate in `kernel.inc`, bump
> `KERN_JUMPTAB_SIZE` and the `.assert` guarding the table size, and document
> the new row here. Never reorder existing entries — that breaks the ABI.
> Appending moves only the code after the table, never an existing entry.
> BASIC and WozMon don't `.include kernel.inc`: they take the table's base
> from the linker (`__KERNEL_START__`) and add the entry's offset, so they
> need an equate only for an entry they call.

---

### Taking over the IRQ

At reset the kernel starts VIA Timer 1 (an IRQ every 6250 PHI2 cycles, 192
times a second at the 1.2 MHz default), puts its handler in `IRQ_VEC`
(`$FFFE`) and enables interrupts. This stays on after
a program replaces BASIC. The handler takes 65-73 cycles per tick (about 1% of
the CPU) and only touches `KJIFFY`, the cursor blink variables (`$037E-$037F`)
and, while `CHRIN` waits, the cursor.

A program has four options:

- **Leave it.** Nothing to do.
- **Change its rate.** Timer 1 reloads from its latch (`VIA_T1LL`/`VIA_T1LH`,
  `$C006`/`$C007`) every period, so a new count written there takes effect
  from the next period. From BASIC, `POKE 49158,lo:POKE 49159,hi`; for
  example `212,48` (12,500 cycles) halves the rate. `KJIFFY` and the cursor
  blink (a toggle every 80 ticks) follow it. `TI` and key repeat don't, since
  they come from MIA.
- **Stop it.** Write `$40` to `VIA_IER` (`$C00E`) to turn off only the Timer 1
  IRQ, or `SEI` to mask every IRQ. `KJIFFY` and the cursor blink stop with it.
- **Chain to it.** Point `IRQ_VEC` at the program's own handler (with IRQs
  masked while writing the two bytes). The handler does its work, restores A,
  X and Y to their values at entry, and ends with `JMP KERN_IRQ`, which saves
  them again, does the kernel's work and returns with `RTI`. Two rules:
  - If the handler wants MIA's interrupts, it reads `IRQ_STATUS_H` and then
    `IRQ_STATUS_L` before chaining, because the kernel's handler read-clears
    them.
  - If it uses MIA's index windows or `CFG_SELECT`, it brackets that work
    with `MIA_CTX` push and pop (§11), as the kernel does.

Put the kernel's handler back before returning to BASIC with `RTS`, or the
vector may point into memory BASIC reuses. `KERN_WARMSTART` and reset restore
it automatically.

## 7. Kernel code and data (after `DIR_NAME_BUF`, from `$045E` today)

Internal routines (`KERNCODE`/`RODATA`/`WOZCODE` segments). These addresses
are **not** ABI; reach them only through the jump table. The kernel+WozMon
portion of the image is ~4.4 KiB (`$0400`-`$15A8` today); see §8 for the
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
  and Timer 1 free-runs as the kernel tick (`KJIFFY` and the cursor blink).
- `irq_handler` / `nmi_handler` — `irq_handler` (also `KERN_IRQ`, §6)
  read-clears MIA `IRQ_STATUS_L`, counts VIA Timer 1 ticks in `KJIFFY`, and
  toggles the cursor only while `CHRIN` is
  polling for input. The toggle is bracketed by `MIA_CTX` push and pop (§11),
  so the code it interrupts finds window A and `CFG_SELECT` as it left them.
- `mia_mem_*` (`memory.s`) — raw MIA RAM read, write, copy, fill, and the
  rectangle copy and fill behind BASIC's `MCOPY`/`MFILL`; see
  `docs/basic-memory.md`.

---

## 7.5. `DIR_NAME_BUF` (right after the jump table, `$0436–$045D` today)

`DIR_NAME_BUF` (40 bytes) is a transient scratch buffer `DIR`
(`docs/basic-file.md`) reads one directory entry's name into before printing
any of it. BASIC declares it in `src/basic/clementina_extra.s`, in the
`DIRBUF` segment, which `clementina.cfg` places right after the jump table so
it sits outside BASIC's reclaimable region. Nothing else uses its address and
nothing needs it to survive between `DIR` invocations, so it simply moves up
3 bytes whenever the jump table grows. It is part of the loaded image (40
zero bytes in `kernel.bin`).

Until 2026-10-13 the image started at `$04B7`. That left `$0400–$048E`
(143 bytes, once the retired background-`PLAY` control block, `BGP_*`)
unused, with this buffer fixed at `$048F`. Moving the image down to `$0400`
closed the gap; those bytes went to BASIC's heap.

---

## 8. BASIC free workspace (`__BASICMEM_LAST__ … $BFFF`)

**2026-09-14 bottom-anchor rework** (reversing the 2026-09-13 top-anchored/
descending-loader design). BASIC's program text, variables, arrays, and
strings live between `TXTTAB` and `MEMSIZ`, exactly as before - what changed
is where the *image* sits relative to that heap. The loaded kernel+WozMon+
BASIC image briefly sat **above** the heap (ending exactly at `$BFFF`,
descending-loader design); it is now bottom-anchored instead, sitting
**below** the heap, starting exactly at `$0400` (right after working RAM)
and growing upward through **KERNEL → WOZMON → BASIC** - see §13 for the
loader that makes this possible with zero wasted address space, in a single
`ld65` pass (no two-pass "measure, then relink" build needed: a fixed
*start* lets the linker place everything forward natively, unlike a fixed
*end*, which needs the start computed backward from the total size first).

Concretely: `KERNEL` (`clementina.cfg`) is a generously-sized MEMORY region
(`$0400`, size `$1200`) holding the jump table, `DIR_NAME_BUF` and kernel+WozMon; `BASICMEM` starts immediately
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

With the current ~24.1 KiB image (kernel+WozMon+BASIC, `$0400`-`$6456`
today), this gives BASIC **23,465 bytes free** (`$6457` to `$BFFF`) - an
image that
needs no manual boundary maintenance as commands are added: there is no
`MAX_KERNEL_BYTES`-style hand-maintained ceiling. `KERNEL`'s own `$1200`
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
> it (`$6457` today) and moves only as the image itself grows/shrinks, but the
> root cause is still not diagnosed - re-check this if the image's size changes
> enough to approach that window.

Bank 0 must remain selected while BASIC is active - the image itself
(kernel+WozMon+BASIC, ~24.0 KiB) fits entirely below `$8000` today, but the
**heap** above it does not: `TXTTAB`..`MEMSIZ` spans from `$6457` up through
`$BFFF`, so its upper ~16 KiB (program text/variables/arrays/strings, once
the heap grows that far) lives in Extended RAM bank 0. Changing PA0-PA4 away
from bank 0 while BASIC is still running would therefore replace part of the
live heap out from under it; kernel warm start restores bank 0 before
returning to the interpreter. BASIC's `BANK` statement doesn't map a bank
itself: `BLOAD`, `BRUN`, `BSAVE`, `PEEK`, `POKE` and `SYS` map the bank it
picked only while they work at `$8000-$BFFF`, then map bank 0 back (§9).

### Where machine code can go

`BLOAD` and `BRUN` write wherever the file or `addr` says
(`docs/basic-file.md`); the choice of a safe place is the programmer's.

- **Code that takes over the machine** (started with `BRUN`) may
  overwrite BASIC: anywhere from `$1600` up. Below that is the kernel, which
  holds the loader itself, so a load there crashes mid-copy. `KERNEL`'s region
  ends at `$15FF` however the kernel grows. The SDK templates use `$1800`.
- **Code that returns to BASIC** (called with `SYS`) must leave BASIC intact:
  `$0280-$02F7` (§4), banks 1-31 (§9), or the top of bank 0 after lowering
  `MEMSIZ`. `POKE 63,lo:POKE 64,hi:CLEAR` moves the top of BASIC's memory
  down, as `POKE 55/56` does on the C64; for example `POKE 63,0:POKE 64,176:
  CLEAR` frees `$B000-$BFFF` (4 KiB) until the next cold start. Note the
  keyword is `CLEAR`, not the C64's `CLR`.

---

## 9. Extended RAM (`$8000–$BFFF`)

A 16 KiB window into 512 KiB of banked RAM. The active 16 KiB bank is
selected by VIA Port A bits PA0–PA4 (32 banks). Bank 0 holds the upper part
of BASIC's heap (§8) whenever it grows past `$8000` — it is not ordinary
free storage the way banks 1–31 are, and must be selected again before
resuming BASIC after using any other bank. Banks 1–31 are entirely free for
bank-aware access: BASIC's `BANK n` picks one for `BLOAD`, `BRUN`, `BSAVE`,
`PEEK`, `POKE` and `SYS` (`docs/basic-file.md`), and a RAM disk, paged
data/assets, or large buffers can live there too. `BANK 0` is safe above a
lowered `MEMSIZ` (§8).

---

## 10. I/O (`$C000–$DFFF`)

Eight 1 KiB device slots decoded from this 8 KiB region.

| Range | Slot | Device |
| --- | --- | --- |
| `$C000–$C3FF` | 0 | **65C22 VIA**. Port A drives Extended RAM banking; Port B, CA1/CA2 and CB1/CB2 are free and wired to the user port header. Registers repeat every 16 bytes within the slot. Timer 1 is configured by the kernel as a free-running IRQ source for cursor blink. |
| `$C400–$DFFF` | 1–7 | Free I/O slots, one per `IOCS1`–`IOCS7` line on the expansion bus headers. A card claims a slot by jumpering one of those lines. |

> Hardware note: `IRQB` is a wired-AND line. MIA and the VIA each pull it low
> through a Schottky diode against a 4.7 kΩ pull-up, so neither output can fight
> the other. Expansion cards join the same way (their own Schottky diode or an
> open-drain output). `NMIB` (4.7 kΩ) and `RDY` (1 kΩ) are also pulled up on the
> board and exposed on the expansion headers, so cards can pull them low too.
> The IRQ handler has to poll each possible source (VIA `IFR`, MIA, any cards)
> to find out which one asserted the line.

---

## 11. MIA region (`$E000–$FFFF`)

MIA (the Raspberry Pi Pico 2 W interface adapter) owns this region. The board
selects MIA for all of `$E000–$FFFF`, but MIA is wired to A0–A4 only, so it
sees just its 32 registers: `$FFE0–$FFFF`, repeated every 32 bytes across
`$E000–$FFDF`. A mirror is the same register, side effects included: reading
`$E010` clears pending IRQs like `$FFF0`, and writing `$E009` triggers a
command like `$FFE9`. Programs use `$FFE0–$FFFF` only and never touch
`$E000–$FFDF`.

### MIA register block (`$FFE0–$FFFF`)

All 32 registers, named in [`src/include/mia.inc`](../src/include/mia.inc), which `kernel.inc` and BASIC include. clementina-sdk generates that file from its specs, under MIA's own names.

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
| `$FFF2` | `INPUT_STATUS` | Text availability, held-input summaries, active source. Bit 0 = `INPUT_TEXT_READY`. |
| `$FFF3` | `INPUT_CHAR` | Read-to-pop text FIFO. Returns `$00` when empty. PETSCII-compatible bytes. |
| `$FFF4` | `INPUT_CHAR_COUNT` | Number of bytes queued in the text FIFO. |
| `$FFF5` | `MIA_CTX` | Context stack for interrupt handlers: write `$01` to save the index-window, CFG and command-parameter state, `$02` to restore it. See clementina-mia's README, "Context stack". |
| `$FFF6–$FFF9` | reserved | Read as zero. |
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

## 12. MIA RAM and index descriptors

### MIA RAM map

MIA RAM is split at `$14000`. The MIA firmware owns everything below it and
programs own everything above it. The authoritative table is the "MIA RAM map"
in `clementina-mia`'s README.

| Range | Size | Owner | Use |
| --- | --- | --- | --- |
| `$00000-$10D4F` | 68,944 B | MIA video | Local header and render control, palettes (`$00100`), CHR banks (`$00200`), background nametables and attributes (`$0C200`), overlay (`$10080`), OAM (`$10850`) |
| `$11000-$1107F` | 128 B | MIA input | Input state; clock snapshot at `$11078-$1107F` |
| `$12000-$1204F` | 80 B | MIA audio | Audio registers |
| `$13000-$13BFF` | 3 KiB | MIA SD/FS | Control block and buffers |
| `$14000-$3FFFF` | 176 KiB | **Programs** | Free. Decimal 81920-262143. |

Rules for programs:

- `$14000-$3FFFF` is yours. The firmware writes there only where a program
  points it (an index, a DMA copy, an SD transfer, a sequencer track), and no
  reset clears it. The serial console's `audio seq test` debug command is the
  one exception: it writes the top 1 KiB.
- The gaps below `$14000` (`$10D50-$10FFF`, `$11080-$11FFF`, `$12050-$12FFF`,
  `$13C00-$13FFF`) belong to the firmware, kept for its future state.
- Write below `$14000` only through the documented video, input, audio and
  SD/FS layouts.
- BASIC's `TRACK` puts voice `v` at `$14000 + v * $1000` when no address is
  given, so a BASIC program with background music shares the start of the
  block with it.

### Index descriptors

MIA RAM is reached only through index descriptors. A descriptor is a 24-bit
current address into MIA RAM plus a default address, a limit, a step and flags.
There are 256 of them, ids `$00-$FF`. A program binds one to window A or B
(`IDXA_SELECT`/`IDXB_SELECT`) and then reads or writes MIA RAM through that
window's data port.

### Who owns which id

| Ids | Owner | Use |
| --- | --- | --- |
| `$00-$4F` | **Programs** | Free. Never configured or touched by the firmware, the kernel or BASIC. |
| `$50-$57` | MIA input | Keyboard/keypad bitmap probes (`MIA_INPUT_INDEX_KEYBOARD_PROBE_0-7`) |
| `$58-$5F` | MIA input | Consumer bitmap probes (`MIA_INPUT_INDEX_CONSUMER_PROBE_0-7`) |
| `$60-$68` | MIA input | Input state block, bitmaps, mouse, gamepads `0-3`, input control |
| `$69-$6F` | — | Reserved for MIA input |
| `$70-$72` | MIA video | Local control page (never syncs to the video client) |
| `$73-$7F` | — | Reserved for MIA video local control |
| `$80-$88` | MIA video | Render control page and its fields |
| `$89-$8F` | — | Reserved for MIA video render control |
| `$90-$9F` | MIA video | Palette banks `0-15` |
| `$A0-$A7` | MIA video | CHR banks `0-7`, 6,144 bytes each |
| `$A8-$AF` | MIA video | Background nametables `0-7`, 1,000 bytes each |
| `$B0-$B7` | MIA video | Background attribute tables `0-7`, 1,000 bytes each |
| `$B8-$B9` | MIA video | Overlay nametable and attributes (the console) |
| `$BA-$BF` | — | Reserved for MIA video |
| `$C0-$DF` | MIA video | Direct OAM entries, sprites `0-31`, 5 bytes each |
| `$E0-$E5` | MIA SD/FS | Control, sector, path, directory entry, transfer, second path |
| `$E6-$EB` | MIA audio | Whole audio block, voices `0-3`, header |
| `$EC-$EF` | MIA audio | Per-voice sequencer status |
| `$F0-$F5` | Kernel | Scroll DMA (`$F0-$F3`), memory copy and fill (`$F4-$F5`) |
| `$F6-$FF` | Kernel | Reserved for the kernel |

Rules for programs:

- `$00-$4F` are yours. Nothing else sets or moves them. The SDK game runtime
  (`clementina-sdk` `packages/runtime`) is part of the program that links it
  and takes `$40`/`$41` from this range.
- The MIA-owned ids are the documented way to reach video, input, audio and SD
  memory, so programs use them too. The kernel and BASIC use them as well and
  re-seek before each use, so their current address does not survive a kernel
  call (for example `CHROUT` moves `$B8`/`$B9`).
- Kernel services leave window A bound to whatever id they last used. Rebind
  your windows after calling one.
- The IRQ handler saves and restores both window selections and `CFG_SELECT`
  (`MIA_CTX` push/pop), so a program's bindings survive interrupts.
- Never change `$F0-$FF`.

### Ids the kernel uses

| Index | Purpose | MIA RAM target |
| --- | --- | --- |
| `$90-$97` (`MIA_VIDEO_INDEX_PALETTE_0-7`) | Startup palette upload | palette banks `0-7` |
| `$85` (`MIA_VIDEO_INDEX_BANK_SELECT`) | Select CHR bank `0` for bg/overlay/sprite consumers | render control `$28-$2C` |
| `$86` (`MIA_VIDEO_INDEX_CHR_1BPP`) | Mark CHR bank `0` as 1bpp and use overlay plane `1` | render control `$2D-$2E` |
| `$87` (`MIA_VIDEO_INDEX_BACKDROP_COLOR`) | Select palette `0`, color `0` as the blue backdrop | render control `$2F` |
| `$81` (`MIA_VIDEO_INDEX_LAYER_ENABLE`) | Enable the overlay layer | render control `$21` |
| `$B8` (`MIA_VIDEO_INDEX_OVERLAY_NT`) | Console **write cursor**: bound to window A; positioned per `CURSOR_X/Y` via CFG | overlay nametable cell |
| `$B9` (`MIA_VIDEO_INDEX_OVERLAY_ATTR`) | Console **attribute cursor**: bound to window A after each tile write | overlay attribute cell |
| `$F0` (`KIDX_SCROLL_NT_SRC`) | Kernel-reserved scroll DMA source | overlay nametable + 40, limit = overlay nametable end |
| `$F1` (`KIDX_SCROLL_NT_DST`) | Kernel-reserved scroll DMA destination | overlay nametable base |
| `$F2` (`KIDX_SCROLL_ATTR_SRC`) | Kernel-reserved scroll DMA source | overlay attributes + 40, limit = overlay attributes end |
| `$F3` (`KIDX_SCROLL_ATTR_DST`) | Kernel-reserved scroll DMA destination | overlay attributes base |
| `$F4` (`KIDX_MEMORY_SRC`) | Kernel-reserved source for MIA memory copy, fill and rectangle services (`memory.s`) | any MIA RAM |
| `$F5` (`KIDX_MEMORY_DST`) | Kernel-reserved destination for the same services | any MIA RAM |
| `$60` (`MIA_INPUT_INDEX_INPUT_STATE`) | `input_read_byte`: re-seeked to `$11000` + offset for each read (BASIC input functions, timing) | input state block |
| `$E0`, `$E4` | `KERN_LOAD`: SD/FS control block and transfer buffer | SD/FS block |

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
`scroll_up` uses `MIA_CMD_COPY_INDEXES` with byte count `0` to copy each source
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
what lets the image start exactly at `$0400` with zero wasted space,
regardless of how large it grows: the loader's start address is always the
same fixed constant (`$0400`), and the image's actual *end* — which does
vary release to release — is simply wherever the incrementing writes stop,
never something the firmware needs to know or recompute.

1. MIA powers up in **loader mode**: it writes a tiny self-modifying loader
   into the register block and points RESET at `$FFE0`.
2. The loader streams `kernel.bin` into base RAM **ascending from `$0400`**:
   the first byte transmitted lands at `$0400`, the next at `$0401`, and so
   on, forward through `kernel_data[]` while the write target increments —
   the image ends up in the same byte order it was linked in.
3. MIA switches to **normal mode**: it restores the normal register block and
   sets `RESET_VEC` (and defaults `NMI_VEC`/`IRQ_VEC`) to `$0400` — the fixed
   start of the jump table (§6), same as the loader's own start point.
4. The 6502 is released from reset and jumps to `$0400` → `KERN_COLDSTART`.
5. `COLDSTART` installs real NMI/IRQ handlers into `$FFFA/$FFFE`, initializes
   the console, clears the screen, prints the banner, and enters the loop.

> Two fixed constants drive this, in both the firmware (`clementina-mia`
> `src/mia/sys/mia.c`: `kernel_load_bottom_address`/`kernel_target_address`)
> and the emulator (`clementina-6502` `pkg/components/mia/registers.go`:
> `miaKernelLoadBottomAddress`/`miaKernelTargetAddress`) — both **`$0400`**
> (where the ascending loader starts writing, and the jump table's start /
> the RESET-NMI-IRQ vector target — the same address, since the loader
> direction now matches the jump table's own fixed position). Neither needs
> to change as the ROM image grows or shrinks — that's the whole point of
> anchoring to a fixed low start. They would only need to move together if
> the working-RAM footprint below `$0400` itself changed, which is rare and
> deliberate (the last move, from `$04B7`, is in §7.5).

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
of KJIFFY and PHI2. MIA latches the snapshot into its RAM at `$11078–$1107F`;
`KERN_RDTIM` copies it to `CLOCK_SNAPSHOT` (`$02F8–$02FF`, §4), where BASIC and
machine code read it. `KERN_SETTIM` sets the 60 Hz count. `DELAY`'s scratch
bytes are linked into the loaded image. See [BASIC timing](basic-timing.md).

## General MIA RAM operations

BASIC `MPEEK`, `MPOKE`, `MCOPY`, and `MFILL` address MIA RAM `$00000–$3FFFF`,
independently of CPU RAM and VIA bank selection. Program data goes in
`$14000–$3FFFF` (§12). Kernel scratch descriptors
`$F4` and `$F5` are reserved for these operations; argument and temporary bytes
are linked into the loaded image. See [BASIC MIA memory](basic-memory.md).

# Mapping the Clementina

A location-by-location map of the Clementina 6502 address space, in the spirit
of *Mapping the Commodore 64*. It describes the current build: when the kernel,
BASIC or the hardware change, change it with them. How the layout got here is
in [history/memory-map.md](history/memory-map.md).

- Hardware decoding: the Go emulator (`clementina-6502`,
  `pkg/computers/clementina`), the MIA firmware (`clementina-mia`) and the
  schematics ([clementina-hardware](https://github.com/fran150/clementina-hardware)).
- Kernel symbols: [`src/kernel/kernel.inc`](../src/kernel/kernel.inc). If you
  change an address there, change it here.
- Shared tables: clementina-sdk's specs list every zero-page location (BASIC's
  included), system page variable and VIA register
  ([`cpu-memory-map.json`](https://github.com/fran150/clementina-sdk/blob/main/specs/cpu-memory-map.json)),
  the MIA RAM map
  ([`mia-ram-map.json`](https://github.com/fran150/clementina-sdk/blob/main/specs/mia-ram-map.json))
  and all 256 index ids
  ([`mia-indexes.json`](https://github.com/fran150/clementina-sdk/blob/main/specs/mia-indexes.json)).
  Its drift check compares them with MIA's headers and this build, so this
  page summarizes those tables instead of copying them.

Numbers are hexadecimal unless noted. "MIA RAM" means the 256 KiB internal to
MIA, reached only through the indexed windows — it is **not** in the 6502
address space. §12 maps it.

---

## 1. The big picture

The 65C02 sees 64 KiB. Decoding (from the Clementina CS logic):

| Range | Size | Region | Notes |
| --- | --- | --- | --- |
| `$0000–$7FFF` | 32 KiB | **Base RAM** | Flat, always present. Holds zero page, stack, the kernel image, and BASIC's workspace. |
| `$8000–$BFFF` | 16 KiB window | **Extended RAM** | A 16 KiB window into 512 KiB of banked RAM. Bank selected by VIA Port A (PA0–PA4 → 32 banks, §9 and §10). |
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
| `$0400–$044D` | Kernel jump table, with BASIC's entry points at the end (§6), the first bytes of the loaded image |
| `$044E–…` | Rest of the image: `DIR_NAME_BUF` (§7.5), kernel+WozMon (§7), then BASIC (§8) |
| `…–$BFFF` | BASIC's free workspace / heap (§8), filling everything above the image |

The image is anchored at `$0400` and grows upward: the jump table,
`DIR_NAME_BUF`, the kernel, WozMon, then BASIC. BASIC's heap fills everything
above it up to `$BFFF`, so base RAM has no unused gap. The image fits below
`$8000` but the heap does not, so the heap's upper 16 KiB is Extended RAM
bank 0, which stays selected while BASIC runs (§8, §9). Everything from `$1600`
up can be reclaimed by a program that no longer needs BASIC (§8).

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

BASIC's own locations are not listed here one by one. clementina-sdk's
[`cpu-memory-map.json`](https://github.com/fran150/clementina-sdk/blob/main/specs/cpu-memory-map.json)
(`pages`, `ZERO_PAGE`) has every zero-page location with its name, size and
owner, BASIC's 67 included, checked against this build's symbols.

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
| `$0302` | `TEXT_ATTR` | 1 | Live overlay pen: the attribute byte (§12) for new console cells. Bits `0-3` select the palette bank; the default, `$00`, is palette `0`, white text over the blue backdrop. BASIC output drives this transiently; the editor reasserts `EDITOR_PEN` into it whenever it takes control. |
| `$0303` | `LAST_KEY` | 1 | Debug: last byte returned by `CHRIN`. Watch this in the emulator's memory window to confirm input before attaching a video client. |
| `$0304` | `EDITOR_PEN` | 1 | Persistent editor pen. The pen the screen editor sets from the keyboard (ESC commands) and reasserts into `TEXT_ATTR` at each line edit, so the cursor and typed text keep their color across BASIC output (LIST, messages, styled `PRINT`). |
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
| `$03D0` | `EDIT_MODE` | 1 | Glyph mode (`0..2`), used by the editor to map typed `$20-$7E` to alternate tile ranges ([phase5-charset-keyboard.md](phase5-charset-keyboard.md)). |
| `$03D1` | `EDIT_PAINT` | 1 | Nonzero while Paint mode is active. |
| `$03D2` | `EDIT_CMD_PENDING` | 1 | Nonzero between `ESC` and its command key. |
| `$03D3–$03FC` | `STYLE_SIDE_BUF` | 42 | BASIC tokenizer scratch for styled program-literal sidecars ([styled-strings.md](styled-strings.md)). Captures compact literal attribute records before appending them to the stored program line. `$03D3–$03D4` are also reused as a transient LIST line-pointer save, and `$03D3–$03F8` (38 bytes) as `TRACK`'s MML-compile-time state (including its optional explicit-address parse, JUMP-delta scratch and `&` tie state) and `BAND`/`VTAKE`/`VGIVE`'s voice-mask scratch (tokenizer and `TRACK`/`BAND`/`VTAKE`/`VGIVE` never run at the same moment). |
| `$03FD` | `BASIC_DEFAULT_ATTR` | 1 | BASIC default output attribute set by `COLOR`, `FLIPX`, `FLIPY`, and `ALT`. |
| `$03FE` | `BASIC_STYLE_MASK` | 1 | BASIC style override mask set by `STYLE n`, stored in overlay-attribute bit form (`$0F`, `$10`, `$20`, `$80`). |
| `$03FF` | `STYLE_BASE_LEN` | 1 | BASIC tokenizer scratch: tokenized line length before any style sidecar is appended. |

---

## 6. Kernel jump table (`$0400–$044D`)

The **stable ABI**. Each entry is a 3-byte `JMP`. Callers (BASIC, WozMon, user
programs) bind to these fixed addresses; the routines behind them may move
freely.

The jump table is the first segment in `clementina.cfg`, so it is always the
bottom 78 bytes of the image, `$0400-$044D`, however large the rest grows.
The last eight entries, `BAS_*`, lead into BASIC (see "Calling BASIC from
machine code" below).
`KERN_BASE` (`kernel.inc`) is the constant `$0400`.

| Addr | Symbol | In | Out | Description |
| --- | --- | --- | --- | --- |
| `$0400` | `KERN_COLDSTART` | — | — | Reset entry. MIA points RESET here. Sets up the machine, console, prints the banner, then enters BASIC. |
| `$0403` | `KERN_WARMSTART` | — | — | Re-enter BASIC at the READY prompt, **preserving** the current program and variables. Resets the stack, puts the kernel's handler back in `IRQ_VEC`, sets the VIA up as reset does (§10), and re-enables interrupts first, so it is safe to reach mid-statement (used by WozMon's `Q` quit command; `BFD3R`-style manual re-entry still works). |
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
| `$0436` | `BAS_CHKCOM` | `TXTPTR` at a comma | `TXTPTR` past it, `A` = next character | Skip the comma at `TXTPTR`; anything else raises `SYNTAX ERROR`. |
| `$0439` | `BAS_FRMNUM` | `TXTPTR` at an expression | `FAC` = value, `TXTPTR` past it | Evaluate a numeric expression; a string raises `TYPE MISMATCH`. |
| `$043C` | `BAS_FRMEVL` | `TXTPTR` at an expression | `FAC`, `VALTYP` (`$17`), `TXTPTR` past it | Evaluate any expression. `VALTYP` is `$FF` for a string, whose descriptor address is then in `FAC+3`/`FAC+4`. |
| `$043F` | `BAS_GETADR` | `FAC` = 0-65535 | `LINNUM` (`$11`), `A` = high, `Y` = low | Convert `FAC` to a 16-bit unsigned value; outside 0-65535 raises `ILLEGAL QUANTITY`. |
| `$0442` | `BAS_GETBYT` | `TXTPTR` at an expression | `X` = value, `A` = next character | Evaluate a numeric expression 0-255; outside it raises `ILLEGAL QUANTITY`. |
| `$0445` | `BAS_PTRGET` | `TXTPTR` at a variable name | `VARPNT` (`$4F`), `A` = low, `Y` = high | Find the variable, or create it, and return the address of its value. |
| `$0448` | `BAS_ERROR` | `X` = error code | (does not return) | Raise a BASIC error: print `?`, its message and ` ERROR` (and ` IN` with the line number in a program), then return to `READY`. The codes are the offsets `ERR_*` in `src/basic/error.s`. |
| `$044B` | `BAS_LINPRT` | `A` = high, `X` = low | `A`/`X`/`Y` clobbered | Print the 16-bit value as an unsigned decimal, with `PRINT`'s leading space. |

> When you add a kernel call, append a new `JMP` to the table in
> `src/kernel/kernel.s`, add the `KERN_*` equate in `kernel.inc`, bump
> `KERN_JUMPTAB_SIZE` and the `.assert` guarding the table size, and document
> the new row here. Never reorder existing entries — that breaks the ABI.
> Appending moves only the code after the table, never an existing entry.
> BASIC and WozMon don't `.include kernel.inc`: they take the table's base
> from the linker (`__KERNEL_START__`) and add the entry's offset, so they
> need an equate only for an entry they call.

### Calling BASIC from machine code

Machine code that BASIC calls with `SYS` or `USR` can use BASIC's own routines
to read its arguments, print a number or raise an error, through the `BAS_*`
entries. They stay at the same address whatever the build, like the rest of
the table. The routines behind them live in BASIC, so the entries work only
while BASIC is in memory, not in a program that has loaded over it.

`SYS` leaves `TXTPTR` just past the address, so a routine reads arguments
written after it. For `SYS 49152,10,4660`, the routine calls `BAS_CHKCOM`
then `BAS_GETBYT` for the 10 (in `X`), then `BAS_CHKCOM`, `BAS_FRMNUM` and
`BAS_GETADR` for the 4660 (in `Y`/`A` and `LINNUM`), and returns with `RTS`;
BASIC goes on with whatever follows on the line. An error raised on the way,
by these routines or by `BAS_ERROR`, maps bank 0 back first, so a routine
running in another bank can raise one safely.

`USR(x)` hands its argument over in `FAC`. Zero page holds four older vectors
that also stay put: `GOSTROUT` (`$03`, `JMP` to the routine that prints the
string at `A`/`Y`), `GOAYINT` (`$06`, address of the routine that converts
`FAC` to a 16-bit integer in `FAC+3`/`FAC+4`), `GOGIVEAYF` (`$08`, address of
the routine that converts the integer in `A`/`Y` to `FAC`) and `USR` (`$0A`,
the `JMP` that `USR()` calls).

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

Reset and warm start (`KERN_WARMSTART`, WozMon's `Q`) start Timer 1 again at
6250 with its IRQ on, whatever the program changed (§10).
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
it automatically. To take interrupts from another VIA source, see "Using
another VIA interrupt" in §10.

---

## 7. Kernel code and data

Internal routines (`KERNCODE`/`RODATA`/`WOZCODE` segments). These addresses
are **not** ABI; reach them only through the jump table. In the current build
the segments sit as below; `build/kernel.map` lists them for any build.

| Segment | Range | Holds |
| --- | --- | --- |
| `JUMPTAB` | `$0400–$044D` | The jump table (§6) |
| `DIRBUF` | `$044E–$0475` | `DIR_NAME_BUF` (§7.5) |
| `KERNCODE` | `$0476–$147F` | Kernel code, one translation unit (`kernel.s` includes the other files) |
| `RODATA` | `$1480–$14C8` | The startup banner text |
| `WOZCODE` | `$14C9–$15BE` | WozMon |

All of these sit in the `KERNEL` region of `clementina.cfg`, `$0400–$15FF`;
`ld65` fails the build if they outgrow it. BASIC starts right after the last
one (§8). Notable internal routines:

- `video_init` (`video.s`): through `MIA_VIDEO_INDEX_BANK_SELECT` it picks CHR
  bank 0 for the background, background alt, overlay and sprite layers and
  bank 1 for the overlay alt; it marks banks 0 and 1 as 1bpp with the overlay
  on plane 0, points the scroll indexes `$F0–$F3` at the overlay, writes
  backdrop palette 0 color 0, enables video with `MIA_CMD_VIDEO_SET_MODE`,
  turns on the overlay layer and asks for a full refresh. It loads no font and
  no palette: MIA's firmware and the emulator do that when video starts.
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
- `chrout_glyph` / `put_glyph_raw` — draw a byte as a raw tile, with no control
  codes (behind `KERN_CHROUT_GLYPH`).
- `set_idxa_addr` / `set_idxa_limit` — write the current/limit address of the
  index selected in window A through the CFG registers.
- `newline` / `scroll_up` — row advance and DMA-assisted scroll: kernel-reserved
  indexes `$F0-$F3` copy the overlay nametable and attributes up by one row,
  then the last row is blanked through `$B8/$B9`.
- `edit_line` / `harvest_line` (`editor.s`) — the screen editor behind
  `KERN_EDITKEY`: ESC commands, glyph modes, Paint mode, and the harvest of the
  logical line under the cursor into `EDIT_BUF`/`EDIT_ATTR_BUF`.
- `via_init` / `exram_select_basic_bank` (`interrupts.s`) — set up the VIA,
  Extended RAM bank 0 included, at reset and warm start (§10).
- `irq_handler` / `nmi_handler` — `irq_handler` (also `KERN_IRQ`, §6)
  read-clears MIA `IRQ_STATUS_L`, counts VIA Timer 1 ticks in `KJIFFY`, and
  toggles the cursor only while `CHRIN` is
  polling for input. The toggle is bracketed by `MIA_CTX` push and pop (§11),
  so the code it interrupts finds window A and `CFG_SELECT` as it left them.
  `nmi_handler` is a bare `RTI`.
- `load` (`load.s`) — `KERN_LOAD`, the kernel-resident file loader (§8).
- `mia_mem_*` (`memory.s`) — raw MIA RAM read, write, copy, fill, and the
  rectangle copy and fill behind BASIC's `MCOPY`/`MFILL`; see
  `docs/basic-memory.md`.

---

## 7.5. `DIR_NAME_BUF` (right after the jump table)

`DIR_NAME_BUF` (40 bytes, `$044E–$0475`) is a transient scratch buffer `DIR`
(`docs/basic-file.md`) reads one directory entry's name into before printing
any of it. BASIC declares it in `src/basic/clementina_extra.s`, in the
`DIRBUF` segment, which `clementina.cfg` places right after the jump table so
it sits outside BASIC's reclaimable region. Nothing else uses its address and
nothing needs it to survive between `DIR` invocations, so it simply moves up
3 bytes whenever the jump table grows. It is part of the loaded image (40
zero bytes in `kernel.bin`).

---

## 8. BASIC free workspace (`__BASICMEM_LAST__ … $BFFF`)

BASIC's program text, variables, arrays and strings live between `TXTTAB` and
`MEMSIZ`, above the image:

- `BASICMEM` (`clementina.cfg`) starts right after the `KERNEL` region's
  content (`__KERNEL_LAST__`) and holds BASIC's own code, tables and
  extensions.
- `TXTTAB`, the bottom of the heap, is `__BASICMEM_LAST__`, where BASIC's image
  ends. BASIC's cold start (`init.s`) takes it from the linker instead of
  running msbasic's RAM probe, which writes test patterns and would corrupt the
  running image.
- `MEMSIZ`, the top, is `$C000`, where I/O begins.

So the heap gets every byte the image doesn't use, and adding a command only
moves `TXTTAB` up. Run `make` to see the current split; it prints a line like
the one for the current build:

```text
Built build/kernel.bin (24428 bytes): kernel+wozmon $0400-0x15BE, basic 0x15BF-0x636B, heap 0x636C-$BFFF
```

That leaves the heap 23,700 bytes (`$636C–$BFFF`).

> **Known issue: avoid `TXTTAB` in about `$39FE–$3AC0`.** `INPUT` misreads its
> buffer and prompts `??` again when the program text begins in that window.
> The cause is not found yet; the bug predates the Clementina statements.
> `TXTTAB` is far above that window, but check again if the image ever shrinks
> that far.

Bank 0 must stay selected while BASIC is active. The image fits below `$8000`,
but the heap does not: its upper 16 KiB (program text, variables, arrays and
strings, once they grow that far) is Extended RAM bank 0. Mapping another bank
while BASIC runs would swap part of the live heap out from under it; warm start
and any BASIC error map bank 0 again before returning to the interpreter. BASIC's `BANK`
statement doesn't map a bank itself: `BLOAD`, `BRUN`, `BSAVE`, `PEEK`, `POKE`
and `SYS` map the bank it picked only while they work at `$8000-$BFFF`, then
map bank 0 back (§9).

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
lowered `MEMSIZ` (§8). Machine code switches banks itself through the VIA;
see "Switching banks" in §10.

---

## 10. I/O (`$C000–$DFFF`)

Eight 1 KiB device slots decoded from this 8 KiB region.

| Range | Slot | Device |
| --- | --- | --- |
| `$C000–$C3FF` | 0 | **65C22 VIA** (below). Port A selects the Extended RAM bank, Timer 1 is the kernel's tick, and Port B and CA/CB go to the user port. |
| `$C400–$DFFF` | 1–7 | Free I/O slots, one per `IOCS1`–`IOCS7` line on the expansion bus headers. A card claims a slot by jumpering one of those lines. |

> Hardware note: `IRQB` is a wired-AND line. MIA and the VIA each pull it low
> through a Schottky diode against a 4.7 kΩ pull-up, so neither output can fight
> the other. Expansion cards join the same way (their own Schottky diode or an
> open-drain output). `NMIB` (4.7 kΩ) and `RDY` (2.2 kΩ) are also pulled up on
> the board and exposed on the expansion headers, so cards can pull them low
> too. The IRQ handler has to poll each possible source (VIA `IFR`, MIA, any
> cards) to find out which one asserted the line.

### The VIA (`$C000–$C3FF`)

A W65C22S. Its 16 registers repeat every 16 bytes across the slot; programs
use `$C000–$C00F`. clementina-sdk's
[`cpu-memory-map.json`](https://github.com/fran150/clementina-sdk/blob/main/specs/cpu-memory-map.json)
(`via`) lists all 16 with what the kernel does in each. In short:

| Part | Registers | Used for |
| --- | --- | --- |
| Port A, PA0–PA4 | `ORA` `$C001`, `DDRA` `$C003` | The Extended RAM bank, 0-31, mapped at `$8000–$BFFF`. Outputs. |
| Port A, PA5–PA7 | the same | Nothing. Not connected on the board; inputs. |
| Port B, PB0–PB7 | `ORB` `$C000`, `DDRB` `$C002` | Free. On the user port. The kernel never touches them. |
| CA1, CA2, CB1, CB2 | `PCR` `$C00C` | Free. On the user port. |
| Timer 1 | `$C004–$C007`, `ACR` bits 7-6 | The kernel's tick: free-running, an IRQ every 6250 PHI2 cycles. |
| Timer 2, shift register | `$C008–$C00A`, `ACR` bits 5-0 | Free. |
| Interrupts | `IFR` `$C00D`, `IER` `$C00E` | Only Timer 1's is enabled. |

**The user port.** J3, a 2×10 header at the board's edge, carries PB0–PB7,
CA1, CA2, CB1, CB2, `~RESB`, 3.3 V, 5 V and ground. Its pin numbers and the
rules for cards are in clementina-hardware's README
([Connectors](https://github.com/fran150/clementina-hardware#connectors)). The
port pins are 3.3 V logic: never put 5 V on one, and drive LEDs through a
resistor, since the pins have no current limiting.

**Timer 1.** `via_init` starts it at reset in free-running mode with the PB7
output off, reloading from `VIA_T1_RELOAD` (6250), so it interrupts 192 times
a second at MIA's 1.2 MHz default. Each interrupt adds one to `KJIFFY` (§2)
and, while `CHRIN` waits for a key, counts down the cursor blink (a toggle
every 80 ticks). Both follow PHI2, not wall time. "Taking over the IRQ" (§6)
shows how to change its rate, stop it, or chain a handler in front of it.

**What reset and warm start set.** Reset and warm start (`KERN_WARMSTART`,
and WozMon's `Q`) both run `via_init`. It maps bank 0 (`ORA = 0`, then
`DDRA = %00011111`) and resets `DATA_BANK` to 0, turns every interrupt source
off and clears its flag, sets `ACR` bits 7-6 for Timer 1 (bits 5-0 are kept:
0 after reset), loads Timer 1's latch and counter with 6250, and enables its
interrupt. Port B, `DDRB`, `PCR` and Timer 2's count stay as they were. A
program that returns to BASIC with `RTS` from `SYS` keeps everything it set,
so an interrupt source it left on keeps firing into its own handler, if
`IRQ_VEC` still points at one.

#### Switching banks

Write the bank number to `ORA`. The whole byte can go there, because PA5–PA7
are not connected; `KERN_LOAD` and BASIC write it the same way.

```asm
VIA_ORA = $C001

        lda #5
        sta VIA_ORA             ; bank 5 at $8000-$BFFF
        lda $8000               ; ... read and write the bank ...
        stz VIA_ORA             ; bank 0 again before returning to BASIC
        rts
```

- Code running inside `$8000–$BFFF` must not switch away from its own bank:
  the next instruction would come from the new one.
- The kernel's IRQ handler and everything it touches sit below `$8000`, so an
  interrupt in the middle needs no `SEI`.
- A program called with `SYS` returns to BASIC with bank 0 mapped. `SYS` to an
  address in `$8000–$BFFF` maps the `BANK` statement's bank before the call
  and bank 0 after it (§9).

#### Using another VIA interrupt

Every VIA interrupt source but Timer 1 is off after reset. To use one, for
example CA1 on the user port (falling edge after reset; `PCR` bit 0 set makes
it the rising edge):

1. Chain a handler in front of the kernel's, as in "Taking over the IRQ" (§6).
   The kernel's handler clears only Timer 1, so the program's handler clears
   its own flag, by writing that bit back to `IFR`, before it chains.
2. Enable the source by writing `IER` with bit 7 set and the source's bit set.
   Writing it with bit 7 clear turns the source off again.
3. Turn the source off before returning to BASIC with `RTS`, or the kernel's
   handler alone is left to take it: a source that fires with no one to clear
   it holds `IRQB` low, so BASIC hangs in an endless interrupt. Warm start
   turns it off for you.

```asm
VIA_IFR  = $C00D
VIA_IER  = $C00E
IRQ_VEC  = $FFFE
KERN_IRQ = $042A
CA1      = %00000010

ca1_on:
        sei
        lda #<ca1_irq
        sta IRQ_VEC
        lda #>ca1_irq
        sta IRQ_VEC+1
        lda #CA1
        sta VIA_IFR             ; drop a stale CA1 flag
        lda #($80 | CA1)
        sta VIA_IER             ; enable CA1
        cli
        rts

ca1_irq:
        pha
        lda VIA_IFR
        and #CA1
        beq @chain
        sta VIA_IFR             ; clear the CA1 flag
        ; ... the work, leaving X and Y as they were ...
@chain: pla
        jmp KERN_IRQ            ; KJIFFY, the cursor and MIA's IRQ status

ca1_off:
        lda #CA1
        sta VIA_IER             ; bit 7 clear: disable CA1
        sei
        lda #<KERN_IRQ          ; the kernel's handler again
        sta IRQ_VEC
        lda #>KERN_IRQ
        sta IRQ_VEC+1
        cli
        rts
```

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

All 32 registers, named in [`src/include/mia.inc`](../src/include/mia.inc), which `kernel.inc` and BASIC include. clementina-sdk generates that file from its specs, under MIA's own names; [`mia-registers.json`](https://github.com/fran150/clementina-sdk/blob/main/specs/mia-registers.json) adds each register's access type.

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
| `$FFF3` | `INPUT_CHAR` | Read-to-pop text FIFO. Returns `$00` when empty. ASCII text and the key codes in clementina-mia's [`docs/input.md`](https://github.com/fran150/clementina-mia/blob/main/docs/input.md#key-codes). |
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

MIA RAM is 256 KiB, `$00000–$3FFFF`, split at `$14000`. The firmware owns
everything below it: video at `$00000`, input at `$11000`, audio at `$12000`
and SD/FS at `$13000`, with reserved gaps between them. Programs own
`$14000–$3FFFF` (176 KiB, decimal 81920-262143). Every block with its exact
range, size and owner is in clementina-sdk's
[`mia-ram-map.json`](https://github.com/fran150/clementina-sdk/blob/main/specs/mia-ram-map.json),
and clementina-mia's README has the same map.

Rules for programs:

- `$14000-$3FFFF` is yours. The firmware writes there only where a program
  points it (an index, a DMA copy, an SD transfer, a sequencer track), and no
  reset clears it. The serial console's `audio seq test` debug command is the
  one exception: it writes the top 1 KiB.
- The gaps below `$14000` belong to the firmware, kept for its future state.
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

The ids split three ways: `$00-$4F` are the programs', `$50-$EF` are MIA's
(input, video, SD/FS and audio, in that order) and `$F0-$FF` are the kernel's.
Every id with its name and target is in clementina-sdk's
[`mia-indexes.json`](https://github.com/fran150/clementina-sdk/blob/main/specs/mia-indexes.json).

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
| `$85` (`MIA_VIDEO_INDEX_BANK_SELECT`) | `video_init`: CHR bank `0` for the background, background alt, overlay and sprites, bank `1` for the overlay alt | render control `$28-$2C` |
| `$86` (`MIA_VIDEO_INDEX_CHR_1BPP`) | `video_init`: CHR banks `0` and `1` decoded as 1bpp (`CHR_1BPP_BANKS_TEXT_GFX`), overlay on plane `0` (`CHR_1BPP_PLANES_OVERLAY0`) | render control `$2D-$2E` |
| `$87` (`MIA_VIDEO_INDEX_BACKDROP_COLOR`) | `video_init` and `KERN_SET_BACKDROP`: the backdrop selector, palette `0` color `0` (blue) at cold start | render control `$2F` |
| `$81` (`MIA_VIDEO_INDEX_LAYER_ENABLE`) | `video_init`: enable the overlay layer | render control `$21` |
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

The console is MIA's overlay layer: a fixed **40×25** grid of tile codes at MIA
RAM `$10080` (1000 bytes), with one attribute byte per cell at `$10468` (1000
bytes), drawn by the video client on top of every other layer.

- **Tile codes.** `CHROUT` writes the character byte itself as the tile code,
  so tile N is the glyph for ASCII N. There is no screen-code translation.
  Control codes it interprets (§6) never reach the screen; `CHROUT_GLYPH`
  draws any byte as a tile.
- **Font.** `video_init` decodes CHR banks 0 and 1 as 1bpp and has the overlay
  read plane 0 of each. MIA's firmware and the emulator load the charset when
  video starts. With the default `clascii` set, bank 0 holds the 256 glyphs
  and bank 1 the same glyphs reversed, and a cell's `CHR_ALT` attribute bit
  picks bank 1. [phase5-charset-keyboard.md](phase5-charset-keyboard.md) has
  the glyph layout.
- **Attributes.** Bits 0-3 pick the palette bank, bit 4 flips X, bit 5 flips Y,
  bit 6 is priority and bit 7 is `CHR_ALT`. Pixel value 1 draws color 1 of the
  cell's palette bank; pixel value 0 is transparent, so the backdrop shows
  through. `TEXT_ATTR` (§5) is the attribute new cells get; the cold-start
  value `$00` is palette 0, white.
- **Palette.** The kernel loads none. MIA's firmware and the emulator seed all
  16 banks at video start, and the backdrop is palette 0 color 0, blue.
- **Cursor and scrolling.** The console binds `$B8` to window A and sets its
  current address (through the window-A CFG fields) to the cursor cell before
  each write, then does the same with `$B9` for the attribute. `scroll_up`
  copies both planes up one row with `MIA_CMD_COPY_INDEXES` through `$F0-$F3`,
  with byte count `0` so each copy runs to its source limit without moving the
  indexes.

---

## 13. Boot sequence

1. MIA powers up in **loader mode**: it fills the register block with a tiny
   self-modifying loader and points RESET at `$FFE0`.
2. The loader streams `kernel.bin` into base RAM **ascending from `$0400`**,
   in the byte order it was linked in.
3. MIA switches to **normal mode**: it restores the normal register block and
   points `RESET_VEC`, `NMI_VEC` and `IRQ_VEC` at `$0400`, the start of the
   jump table (§6).
4. The 6502 leaves reset and jumps to `$0400`, `KERN_COLDSTART`.
5. Cold start installs the kernel's NMI and IRQ handlers, sets up the VIA
   (§10) and video (§7), clears the screen, prints the banner, enables
   interrupts and enters BASIC's cold start.

The load address is a fixed constant in both loaders: `kernel_load_bottom_address`
and `kernel_target_address` in clementina-mia's `src/mia/sys/mia.c`, and
`miaKernelLoadBottomAddress`/`miaKernelTargetAddress` in clementina-6502's
`pkg/components/mia/registers.go`, all `$0400`. The image size never enters
into it, so a bigger or smaller ROM needs no change there. If `KERN_BASE`
itself ever moves, those constants move with it, and so does the valid-PC
range in clementina-6502's `pkg/computers/clementina/guessing_game_test.go`.

---

## 14. Conventions and how to extend this document

- One section per region; within a section, a table of named locations.
- When you add kernel state, give it a name in `kernel.inc`, place it in the
  `$0300` page (persistent) or the kernel zero-page block (hot/pointer), and
  add a row here.
- When you add a kernel call, follow the rule in §6 and document the row.
- Describe the current build only. When something changes, rewrite the entry
  and put the story of the change, if it is worth keeping, in
  [history/memory-map.md](history/memory-map.md).
- Give each size or boundary that moves with the build once (§8), and say
  where the build prints it.
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

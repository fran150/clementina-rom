# Clementina BASIC — File I/O

Clementina BASIC talks to MIA's SD card through the same FAT filesystem your
computer would see if you plugged the card in — a real hierarchy of files and
directories, not a single flat disk image. This page is the BASIC
programmer's reference; the wire protocol it wraps (the SD/FS control block,
command ids, and the per-handle model) is described in the `clementina-mia`
repo, `docs/sd.md` and `docs/sd-programmer-guide.md`.

## Model

- **16 file handles**, numbered **1–16**, map one-to-one onto MIA's 16
  MIA_SD_CONTROL_HANDLE_SELECT slots — pick a number, `OPEN` it, use it, `CLOSE` it, same
  as every historical BASIC's file numbers. There is no handle allocator.
- Handles are independent: two files can be open at once (say, copying from
  one to another byte by byte), each keeping its own position.
- There is one **current directory**, shared by the whole session — `CD`
  changes it; every relative path in every command below (`OPEN`, `KILL`,
  `MIALOAD`, ...) resolves against it. An absolute path (starting with `/`)
  always means the SD card's root, regardless of the current directory.
- Errors (missing file, disk full, directory not empty, ...) raise `FILE I/O
  ERROR`, the same way a type mismatch raises `TYPE MISMATCH`.

## Statements and functions

| Statement | Arguments | Effect |
| --- | --- | --- |
| `OPEN "file" FOR mode AS #n` | `mode` `INPUT`\|`OUTPUT`\|`APPEND`\|`UPDATE`, `n` 1–16 | Open a file on handle `n`. `OUTPUT` creates/truncates; `APPEND` creates or positions at the end. `UPDATE` opens/creates for reading and writing at position zero without truncation. |
| `CLOSE #n` | `n` 1–16 | Close handle `n`. |
| `BGET#n, v` | `n` 1–16, `v` a numeric variable | Read one byte (0–255) from handle `n` into `v`. Past the end of the file `v` gets `0` and `EOF(n)` turns `1`; there is no error. |
| `BPUT#n, expr` | `n` 1–16, `expr` 0–255 | Write one byte to handle `n`. Values outside 0–255 raise `ILLEGAL QUANTITY`. |
| `SEEK#n, pos` | `pos` 0–4294967295 | Jump handle `n` to byte offset `pos`. |
| `EOF(n)` | `n` 1–16 (function) | `1` once handle `n` has been read past its last byte, else `0`. |
| `KILL "path"` | — | Delete a file or an empty directory. |
| `MKDIR "path"` | — | Create one directory (its parent must already exist). |
| `RMDIR "path"` | — | Remove an empty directory. It shares `KILL`'s routine, so it deletes a file too. |
| `NAME "old" AS "new"` | — | Rename or move a file or directory. |
| `CD "path"` | — | Change the current directory. |
| `DIR` | — | List the current directory. |
| `DIR "path"` | — | List `path` without changing the current directory. |
| `MIALOAD "path", addr` | `addr` 0–16777215 | Load a whole file straight into MIA RAM at a raw address, no CPU byte-touching. It stops at the end of the file or of MIA RAM. MIA files are raw bytes with no header, so `addr` is required. |
| `MIASAVE "path", addr, len` | `addr`, `len` 0–16777215 | Save `len` bytes of MIA RAM starting at `addr` to a file. |
| `LOAD "path"` | — | Replace the current program with a saved one and clear variables. Ends at the `READY.` prompt, also when a program runs it (that program stops there). |
| `SAVE "path"` | — | Save the current program. |
| `BANK n` | `n` 0–31 | Pick the bank that `BLOAD`, `BRUN`, `BSAVE`, `PEEK`, `POKE` and `SYS` use at `$8000-$BFFF`. 0 at power-on and warm start. |
| `BLOAD "path"[, addr]` | `addr` below `$C000` | Load a file straight into CPU RAM at the address in its header (or `addr`, if given), then return to BASIC. |
| `BRUN "path"[, run]` | `run` 0–65535 | Load a file at the address in its header and jump to `run`, or to the first byte loaded when `run` is left out. It never returns. |
| `BSAVE "path", addr, len` | `addr` below `$C000`, `len` 0–65535 | Save `len` bytes of CPU RAM starting at `addr` to a file, in the format `BLOAD` reads. |
| `SYS addr` | `addr` 16-bit CPU address | Call a machine-code routine at `addr` (`JSR`) and continue with the next statement once it returns (`RTS`). |

`OPEN`, `CLOSE`, `BGET#`, `BPUT#`, `SEEK#`, `EOF`, `KILL`, `MKDIR`, `RMDIR`,
`NAME`, `CD`, `DIR`, `LOAD`, `SAVE`, `BANK`, `BLOAD`, `BRUN`, `BSAVE`, and
`SYS` are reserved words. `BGET#`, `BPUT#` and `SEEK#` are single keywords that include the `#`,
so write them with no space before it: `BGET#1,V` works, `BGET #1,V` raises
`SYNTAX ERROR`. `CLOSE #n`, `FLUSH #n` and `OPEN ... AS #n` take a space.

Out-of-range file numbers (0, or above 16) raise `ILLEGAL QUANTITY`. A string
expression is required wherever a path is expected; a number there raises
`TYPE MISMATCH`.

### Byte I/O example

```basic
10 OPEN "SCORES.DAT" FOR OUTPUT AS #1
20 FOR I=1 TO 10
30   BPUT#1, I*I
40 NEXT I
50 CLOSE #1
60 OPEN "SCORES.DAT" FOR INPUT AS #1
70 IF EOF(1) THEN 110
80 BGET#1, B
90 PRINT B
100 GOTO 70
110 CLOSE #1
```

### Directories

```basic
10 CD "GAMES"
20 DIR
30 OPEN "HISCORE.DAT" FOR INPUT AS #1      : REM  resolves to GAMES/HISCORE.DAT
```

`DIR`'s listing is one name per line; a directory's name gets a trailing `/`
(sizes and dates are not printed). `CD` requires an existing directory —
`CD "NOPE"` on a directory that does not exist raises `FILE I/O ERROR` and
leaves the current directory unchanged.

### Program LOAD/SAVE

```basic
10 PRINT "HELLO"
20 END
SAVE "HELLO.BAS"
NEW
LOAD "HELLO.BAS"
RUN
```

`LOAD`/`SAVE` move the current program's own tokenized text (not MIA RAM, and
not related to `MIALOAD`/`MIASAVE` below) between BASIC's workspace and a
file. `SAVE` doesn't touch the running program; `LOAD` replaces it entirely —
variables, arrays, and strings are all cleared exactly like `NEW`, so it
behaves the same whether typed directly or reached from a running program's
own statement (there is no returning to "after the `LOAD`"). A failed `LOAD`
(bad filename, no such file) is caught before anything is touched, so the
current program survives.

`LOAD`/`SAVE` use file handle 16 internally to stream the program through the
same file I/O this whole page describes — close it first if a program has it
open when calling either.

## Loading and running machine code (BANK/BLOAD/BRUN/BSAVE/SYS)

`BLOAD`/`BRUN`/`BSAVE` load and save raw CPU-RAM byte ranges — not BASIC's
tokenized text (that's `LOAD`/`SAVE` above), and not MIA RAM (that's
`MIALOAD`/`MIASAVE`) — the way a C64 loads a game or a sprite/font asset.
`SYS` then transfers control into loaded code and, unlike `USR()` (an
expression function bound once through its own vector), can be called fresh
against any address at any time as a plain statement.

### File format (PRG)

```text
[addr_lo][addr_hi] then the data
```

The classic 2-byte header: the load address, then the bytes. `BSAVE` writes
exactly the format `BLOAD` and `BRUN` read. A file doesn't record a bank;
`BANK` picks it when the file is loaded.

### `BANK n`

`$8000-$BFFF` is the banked window: 32 banks of 16 KiB (0–31). While BASIC
runs, bank 0 is always mapped there, because the top of BASIC's memory, where
its strings live, is in bank 0 (§8/§9 of docs/memory-map.md). `BANK n` doesn't
map anything itself; it picks the bank that `BLOAD`, `BRUN`, `BSAVE`, `PEEK`,
`POKE` and `SYS` use at `$8000-$BFFF`. Each of them maps it only while it
works there, then maps bank 0 back, so strings keep working in between. It is
0 at power-on and warm start. `BANK 32` and up raise `ILLEGAL QUANTITY`.

```basic
10 BANK 3:POKE 32768,42:PRINT PEEK(32768)   ' bank 3's first byte
20 A$="STILL"+" FINE":BANK 0                ' strings are in bank 0
```

Don't switch banks yourself with `POKE 49153,n`: that hides BASIC's strings
until bank 0 is mapped again.

### `BLOAD "path"[, addr]`

Loads `path` into CPU RAM at the address in its header, or at `addr` instead
if given (`addr` omitted or `0` means the header's address), then returns to
BASIC. Bytes from `$8000` up go to the `BANK` bank.

### `BRUN "path"[, run]`

Loads `path` at the address in its header (into the `BANK` bank from `$8000`
up), then jumps to `run`, or to the first byte loaded when `run` is left out
(or `0`), with the `BANK` bank mapped. It never returns, so the program may
overwrite BASIC. To load somewhere other than the header's address, use
`BLOAD`. It masks interrupts while it copies, since the file may overwrite an
IRQ handler, and enables them before jumping.

**Where the bytes go is the programmer's choice.** `BLOAD` and `BRUN` write
to any CPU RAM below `$C000` (only I/O and the MIA region, `$C000` and up,
are refused, with `FILE I/O ERROR` for a header address and `ILLEGAL
QUANTITY` for an `addr`) and don't check what lives there. A `BLOAD` must
leave the kernel and BASIC intact; `docs/memory-map.md` §8 ("Where machine
code can go") lists the safe places: `$0280-$02F7`, banks 1-31, and bank 0
above a lowered `MEMSIZ`. A program started with `BRUN` may overwrite BASIC,
from `$1600` up.

A payload that reaches the top of a bank (`$BFFF`) auto-advances into the
next bank rather than requiring the caller to split the load across bank
boundaries themselves — the same reason a payload can start a few bytes
before `$C000` and still land correctly. A payload that runs past `$7FFF`
from base RAM continues into the `BANK` bank. Loading is entirely
kernel-resident (`KERN_LOAD`, `src/kernel/load.s`): the destination may
overwrite BASIC's own code as it copies, so it cannot call out to any
BASIC-resident routine mid-copy.

### `BSAVE "path", addr, len`

Saves `len` bytes of CPU RAM starting at `addr` to a file, in exactly the
format `BLOAD` reads back. Unlike `BLOAD`, `len` is mandatory (there's no
"file's own length" to fall back on) — the same asymmetry classic BASIC's
`BLOAD`/`BSAVE` have. Bytes from `$8000` up come from the `BANK` bank, which
`BSAVE` maps only while it reads. A length that reaches the top of a bank
auto-advances into the next bank, mirroring `BLOAD`'s own auto-advance, so a
payload that spans a bank boundary round-trips through `BLOAD`/`BSAVE`
unchanged; a save that starts below `$8000` reads on through the `BANK` bank
the same way. Reading memory to write a file never touches currently-executing
code, so `BSAVE` (unlike `BLOAD`) is entirely BASIC-resident — no
self-overwrite hazard to guard against.

### `SYS addr`

Calls the machine-code routine at `addr` (`JSR`) and, once it returns
(`RTS`), continues with the next statement — a plain, repeatable control
transfer, not a bound expression vector like `USR()`. A routine at
`$8000-$BFFF` runs with the `BANK` bank mapped, and bank 0 is mapped back
when it returns. A program meant to take over the machine permanently should
be started with `BRUN` instead; `SYS` is for calling a subroutine and getting
control back. The routine can read arguments written after the address, as in
`SYS 49152,10,4660`, through the kernel's `BAS_*` entries (`BAS_CHKCOM`,
`BAS_GETBYT`, `BAS_FRMNUM`, `BAS_GETADR`; `docs/memory-map.md` §6).

### Example

```basic
10 BANK 1:BLOAD "LEVELS.PRG"     ' bank 1 from $8000 up
20 BANK 2:BLOAD "MUSIC.PRG"      ' bank 2
30 BANK 0:BRUN "GAME.PRG"        ' load per its header, run its first byte
```

```basic
10 FOR I=0 TO 15: POKE 24576+I,I+1: NEXT I
20 BSAVE "DATA.PRG", 24576, 16
30 BANK 1:BSAVE "BANK1.PRG", 32768, 16384   ' the whole of bank 1
```

```basic
10 BLOAD "ROUTINE.PRG", 640      ' a short routine at $0280
20 SYS 640                       ' call it
30 PRINT "back in BASIC"         ' SYS returned - this line still runs
```

## Loading part of a file

`MIALOAD` always loads the whole file. To use part of one, load it into free
MIA RAM and copy the part with `MCOPY`, which also copies rectangles
(docs/basic-memory.md). Assembly programs can load part of a file directly
with MIA's `FS_LOAD_PART` command (SD protocol 7).

## Video/audio asset family

MIA's video and audio state (nametables, attributes, CHR banks, palettes,
sprite OAM) can be bulk-loaded from a `DATA` stream, or bulk-loaded/saved
straight from/to a file — the file-sourced forms share this same SD/FS layer
and use the same error handling as the statements above. See
`docs/basic-video.md` for the full statement list (`NTREAD`/`NTLOAD`/
`NTSAVE`, `ATRREAD`/`ATRLOAD`/`ATRSAVE`, `CHRREAD`/`CHRLOAD`/`CHRSAVE`,
`PALREAD`/`PALLOAD`/`PALSAVE`, `OAMREAD`/`OAMLOAD`/`OAMSAVE`). The `*LOAD`/
`*SAVE` forms take the `"file"` first, then where: `CHRLOAD "FONT.CHR",1`.
Loads take the whole file; `*READ` instead continues reading from the current
`DATA` position.

## Notes and limits

- Sixteen is a firmware limit (`MIA_SD_MAX_HANDLES`), not a BASIC one — it
  comfortably covers copying between files, an open log plus an open asset
  load, and similar everyday cases.
- `CD`'s effect is not undone by a running program ending or by `CLOSE`;
  it persists for the session (until you `CD` again, or the SD card is
  swapped or re-mounted).
- You can swap the SD card between commands, as with a disk drive. The next
  file statement notices the new card and mounts it. Files that were open on
  the old card are gone: using their numbers raises `FILE I/O ERROR`, and
  `CLOSE` frees them. The current directory goes back to the root. Swap only
  while no file statement is running, and `CLOSE` files you wrote first, or
  their last data is lost.
- `MIALOAD`/`MIASAVE` bypass the CPU entirely — they hand the whole transfer
  to MIA as one job, the same as the video/audio `*LOAD`/`*SAVE` statements.
  `BGET#`/`BPUT#` are the CPU-visible, one-byte-at-a-time alternative, for
  when the program needs to look at (or compute) each byte.

## Extended filesystem operations

| Statement/function | Meaning |
| --- | --- |
| `OPEN "file" FOR UPDATE AS #n` | Open or create for reading and writing, positioned at zero; preserve existing contents. |
| `FLUSH #n` | Flush the open file's pending data and metadata to SD without closing it. |
| `FPOS(n)` | Return the selected open file's current byte position. |
| `FSIZE(n)` | Return the selected open file's size in bytes. |
| `FSTAT "path",S,A,D,T` | Assign size, FAT attributes, packed modification date, and packed modification time to numeric variables or array elements. |
| `DISKFREE(0)` | Return free bytes on the current SD volume. Zero identifies the current volume. |
| `SEEK#n,pos` | Set position, now accepting the full unsigned 32-bit range, 0–4294967295. |

`FLUSH` is the BASIC name for firmware `FS_SYNC`; there is no BASIC `SYNC`
alias. `CLOSE` already flushes, so explicit flushing is mainly useful for
checkpoints while a file stays open. It reduces pending filesystem writes but
does not make updates atomic or guarantee protection from power loss.

`FPOS` and `FSIZE` require companion firmware/emulator SD protocol version 6.
They issue `FS_FILE_INFO` (`$89`) for the requested handle, then read the
existing 32-bit position/size fields. Queries do not flush or change position.
Older firmware produces `FILE I/O ERROR` instead of returning stale values.
Existing command IDs, buffers, and saved BASIC token numbers are preserved.

`FSTAT` does not open a file or consume one of the 16 handles. For directories,
size is zero and attribute bit 4 (16) is set. Other FAT bits are read-only (1),
hidden (2), system (4), volume label (8), and archive (32). Date encodes
`(year-1980)*512 + month*32 + day`; time encodes
`hour*2048 + minute*32 + second/2`. Actual timestamp availability depends on the
filesystem clock. Use ordinary floating-point variables for unsigned dates,
times and large sizes; integer variables retain BASIC's signed 16-bit limits.
As with other multi-result statements, an error in a later destination can
leave earlier destinations assigned.

Unsigned 32-bit positions and sizes are represented exactly by this BASIC's
32-bit mantissa. Fractional seek positions truncate after normal BASIC numeric
evaluation; negative values and values at or above 4294967296 are rejected.
Seeking beyond EOF retains the firmware's existing FatFs behavior, which
depends on whether the file is writable.

Free space is computed as `free_clusters * sectors_per_cluster * 512` using
BASIC arithmetic, avoiding a 32-bit byte-count overflow. Very large capacities
are subject to BASIC floating-point precision. The emulator reports space for
its simulated volume, not the host disk's remaining capacity.

```basic
10 OPEN "SETTINGS.DAT" FOR UPDATE AS #1
20 SEEK#1,10
30 BPUT#1,42
40 FLUSH #1
50 PRINT FPOS(1),FSIZE(1)
60 CLOSE #1
70 FSTAT "SETTINGS.DAT",S,A,D,T
80 PRINT S,DISKFREE(0)
```

Run `python3 tests/run_input.py --run 'TestBasicFSExtensions|TestEmulatedMiaFSFileInfo'`
for the extension regression tests. They cover independent handles, nested
queries, updates without truncation, creation, metadata, free space, errors,
and sparse files at 32-bit size/position boundaries.

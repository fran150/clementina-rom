# Clementina BASIC — File I/O

Clementina BASIC talks to MIA's SD card through the same FAT filesystem your
computer would see if you plugged the card in — a real hierarchy of files and
directories, not a single flat disk image. This page is the BASIC
programmer's reference; the wire protocol it wraps (the SD/FS control block,
command ids, and the per-handle model) is described in the `clementina-mia`
repo, `docs/sd.md` and `docs/sd-programmer-guide.md`.

## Model

- **16 file handles**, numbered **1–16**, map one-to-one onto MIA's 16
  SD_HANDLE_SELECT slots — pick a number, `OPEN` it, use it, `CLOSE` it, same
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
| `BGET#n, v` | `n` 1–16, `v` a numeric variable | Read one byte from handle `n` into `v`. |
| `BPUT#n, expr` | `n` 1–16 | Write the low byte of `expr` to handle `n`. |
| `SEEK#n, pos` | `pos` 0–4294967295 | Jump handle `n` to byte offset `pos`. |
| `EOF(n)` | `n` 1–16 (function) | `1` once handle `n` has been read past its last byte, else `0`. |
| `KILL "path"` | — | Delete a file. |
| `MKDIR "path"` | — | Create one directory (its parent must already exist). |
| `RMDIR "path"` | — | Remove an empty directory. |
| `NAME "old" AS "new"` | — | Rename or move a file or directory. |
| `CD "path"` | — | Change the current directory. |
| `DIR` | — | List the current directory. |
| `DIR "path"` | — | List `path` without changing the current directory. |
| `MIALOAD "path", addr[, maxlen]` | `addr` 0–16777215 | Load a file straight into MIA RAM at a raw address, no CPU byte-touching. Omitted/zero `maxlen` reads until EOF or the end of MIA RAM. |
| `MIASAVE "path", addr, len` | | Save `len` bytes of MIA RAM starting at `addr` to a file. |
| `LOAD "path"` | — | Replace the current program with a saved one. |
| `SAVE "path"` | — | Save the current program. |

`OPEN`, `CLOSE`, `BGET#`, `BPUT#`, `SEEK#`, `EOF`, `KILL`, `MKDIR`, `RMDIR`,
`NAME`, `CD`, `DIR`, `LOAD`, and `SAVE` are reserved words.

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

## Video/audio asset family

MIA's video and audio state (nametables, attributes, CHR banks, palettes,
sprite OAM) can be bulk-loaded from a `DATA` stream, or bulk-loaded/saved
straight from/to a file — the file-sourced forms share this same SD/FS layer
and use the same error handling as the statements above. See
`docs/basic-video.md` for the full statement list (`NTREAD`/`NTLOAD`/
`NTSAVE`, `ATRREAD`/`ATRLOAD`/`ATRSAVE`, `CHRREAD`/`CHRLOAD`/`CHRSAVE`,
`PALREAD`/`PALLOAD`/`PALSAVE`, `OAMREAD`/`OAMLOAD`/`OAMSAVE`); the `*LOAD`/
`*SAVE` forms take a trailing `"file"` argument, `*READ` instead continues
reading from the current `DATA` position.

## Notes and limits

- Sixteen is a firmware limit (`MIA_SD_MAX_HANDLES`), not a BASIC one — it
  comfortably covers copying between files, an open log plus an open asset
  load, and similar everyday cases.
- `CD`'s effect is not undone by a running program ending or by `CLOSE`;
  it persists for the session (until you `CD` again, or the SD card is
  re-mounted).
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

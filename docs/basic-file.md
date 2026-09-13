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
| `OPEN "file" FOR mode AS #n` | `mode` `INPUT`\|`OUTPUT`\|`APPEND`, `n` 1–16 | Open a file on handle `n`. `OUTPUT` creates/truncates; `APPEND` creates or positions at the end. |
| `CLOSE #n` | `n` 1–16 | Close handle `n`. |
| `BGET#n, v` | `n` 1–16, `v` a numeric variable | Read one byte from handle `n` into `v`. |
| `BPUT#n, expr` | `n` 1–16 | Write the low byte of `expr` to handle `n`. |
| `SEEK#n, pos` | `pos` 0–16777215 | Jump handle `n` to byte offset `pos`. |
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

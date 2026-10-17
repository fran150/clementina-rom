# Memory map history

How the image layout, the boot loader and the jump table reached their current
form. The current map is [../memory-map.md](../memory-map.md).

## The code budget (before 2026-09-14)

The combined kernel and BASIC image used to have a fixed ceiling, the
Makefile's `MAX_KERNEL_BYTES`, below a background-`PLAY` control block and
BASIC's workspace. Every new command was budgeted against it. It started at
`$4400` (16,384 bytes), was raised to `$4C00` (18,432) to fit `OAMLOAD`,
`SPRITE` and `BGCHAR`, and then to `$5C00` (22,528) for the SD file commands.
The 2026-09-14 rework below removed the ceiling, and `PLAY` itself was retired
later (see [../basic-sound.md](../basic-sound.md)).

## Top-anchored, then bottom-anchored (2026-09-13 and 2026-09-14)

On 2026-09-13 the image was moved to the top of RAM, ending at `$BFFF`, and
MIA's loader wrote it downwards. One day later (commit `6e2b93c`) it was
anchored at the bottom instead, which is the layout today:

- The image starts at a fixed low address and grows upward, kernel first, then
  WozMon, then BASIC. The jump table is the first segment in
  `clementina.cfg`, so it never moves however large the image gets, and
  `KERN_BASE` became a plain constant.
- MIA's loader writes ascending from that fixed start. Neither the firmware
  nor the emulator needs to know the image size, and `ld65` places everything
  in one pass. A fixed end would need the start computed backward from the
  total size first.
- Everything above the kernel region can be reclaimed. A program that no
  longer needs BASIC loads over it with `BRUN`, the way a C64 game overwrites
  BASIC.

The top anchor had been abandoned because it put about 16 KiB of resident code,
including `CHRGET` and the jump table, inside the banked window at
`$8000-$BFFF`. Any code that switched banks away from bank 0 risked unmapping
its own next instruction.

## The image moves down to `$0400` (2026-10-13)

After the rework the image started at `$04B7`. `$0400-$048E` (143 bytes) held
the background-`PLAY` control block (`BGP_*`), and `DIR_NAME_BUF` was fixed at
`$048F`. Once `PLAY` was retired the block was unused, so commit `da799c4`
moved the image down to `$0400` and the bytes went to BASIC's heap. MIA's
`kernel_load_bottom_address` and `kernel_target_address`, and the emulator's
matching constants, moved with it.

## The jump table loses two stubs (2026-10-11)

`KERN_STOP` and `KERN_SAVE` were removed and every later entry moved down 3 or
6 bytes. Neither stub ever did anything: BASIC checks Ctrl-C itself in
`ISCNTC`, and `SAVE` and `BSAVE` are BASIC-resident wrappers around MIA's file
commands, which machine code can issue directly.

## Retired overlay setup (June 2026)

The first kernel converted ASCII to C64-style screen codes (`char_to_tile`,
removed 2026-06-19) for a PETSCII font in CHR bank 0, plane 1, and uploaded a
blue and white palette through indexes `$90-$97` at cold start. Since the
charset work (2026-06-24) the kernel writes the character byte itself as the
tile code, the overlay decodes plane 0, and MIA's firmware and the emulator
seed all 16 palette banks when video starts.

## Sizes quoted in older copies

Older copies of the memory map gave sizes that went stale as the image grew,
for example "kernel+WozMon `$0400-$15A8`" and "`$6457` to `$BFFF`, 23,465
bytes free". The map now gives the numbers once and points at the line `make`
prints on every build.

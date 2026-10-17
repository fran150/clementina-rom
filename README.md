# Clementina ROM

This repository contains the 6502-side software for Clementina:

- a kernel loaded by MIA at boot
- a Clementina fork/port of Microsoft BASIC
- WozMon

## Build

```sh
make            # build build/kernel.bin (bottom-anchored, starts at $0400)
make install    # copy kernel.bin into the emulator's embedded asset
```

The kernel and BASIC take MIA's register, command, index and memory names from
[src/include/mia.inc](src/include/mia.inc), which clementina-sdk generates from
its specs. Don't edit it here; see [src/include/README.md](src/include/README.md).

## Monitor

From BASIC, type `MON` to enter WozMon. From WozMon, type `Q` to return to the
BASIC `READY.` prompt without clearing the current program.

## Documentation

- [docs/memory-map.md](docs/memory-map.md) — *Mapping the Clementina*, a
  location-by-location map of the address space, the kernel ABI and the VIA.
- [docs/basic-sound.md](docs/basic-sound.md) — BASIC sound statements (`SNDON`,
  `VOL`, `WAVE`, `NOTE`, `FREQ`, `GATE`, `ADSR`, `PULSE`, `PAN`) for MIA's PSG,
  plus the `TRACK`/`BAND`/`VTAKE`/`VGIVE`/`PLAYING`/`CUE` background sequencer.
- [BASIC input](docs/basic-input.md) — keyboard, mouse, gamepad and repeat configuration.
- [BASIC timing](docs/basic-timing.md) — millisecond delays and the 60 Hz TI clock.
- [BASIC MIA memory](docs/basic-memory.md) — byte access, overlapping copies, and block fills.
- [BASIC file I/O](docs/basic-file.md) — file handles, updates, flushing, metadata and free space.
- [BASIC video](docs/basic-video.md) — background, sprites, CHR banks, palettes and the overlay switches.
- [Charset and keyboard glyph entry](docs/phase5-charset-keyboard.md) — glyph modes, ESC styling commands, Paint mode and the charset layout.
- [Styled strings](docs/styled-strings.md) — per-character attributes in BASIC strings and the `COLOR`/`STYLE` policy.
- [Design history](docs/history/README.md) — earlier layouts, phase plans and rejected options, kept out of the reference docs.

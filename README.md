# Clementina ROM

This repository contains the 6502-side software for Clementina:

- a kernel loaded by MIA at boot
- a Clementina fork/port of Microsoft BASIC
- WozMon

## Build

```sh
make            # build build/kernel.bin (bottom-anchored, starts at $04B7)
make install    # copy kernel.bin into the emulator's embedded asset
```

## Monitor

From BASIC, type `MON` to enter WozMon. From WozMon, type `Q` to return to the
BASIC `READY.` prompt without clearing the current program.

## Documentation

- [docs/memory-map.md](docs/memory-map.md) — *Mapping the Clementina*, a living,
  location-by-location map of the address space and the kernel ABI.
- [docs/basic-sound.md](docs/basic-sound.md) — BASIC sound statements (`SNDON`,
  `VOL`, `WAVE`, `NOTE`, `FREQ`, `GATE`, `ADSR`, `PULSE`, `PAN`) for MIA's PSG,
  plus the `TRACK`/`BAND`/`VTAKE`/`VGIVE`/`PLAYING`/`CUE` background sequencer.
- [BASIC input](docs/basic-input.md) — keyboard, mouse, gamepad and repeat configuration.
- [BASIC timing](docs/basic-timing.md) — millisecond delays and the 60 Hz TI clock.
- [BASIC MIA memory](docs/basic-memory.md) — byte access, overlapping copies, and block fills.

- [BASIC file I/O](docs/basic-file.md) — file handles, updates, flushing, metadata and free space.

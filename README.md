# Clementina ROM

This repository contains the 6502-side software for Clementina:

- a kernel loaded by MIA at boot
- a Clementina fork/port of Microsoft BASIC
- WozMon

## Build

```sh
make            # build the kernel image -> build/kernel.bin (loads at $0400)
make install    # copy kernel.bin into the emulator's embedded asset
```

## Documentation

- [docs/memory-map.md](docs/memory-map.md) — *Mapping the Clementina*, a living,
  location-by-location map of the address space and the kernel ABI.

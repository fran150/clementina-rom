# Clementina ROM

This repository contains the 6502-side software for Clementina:

- a kernel loaded by MIA at boot
- a Clementina fork/port of Microsoft BASIC
- an optional monitor
- future utilities such as sprite and sound tools
- programmer-facing documentation for people and agents working on the ROM

MIA is not banked out of high memory. It remains the high-memory device exposed
to the 6502, with its register block at `$FFE0-$FFFF`.

## Current Shape

This repository is intentionally documentation-first while the first kernel is
being designed, but it also contains editable imported source snapshots for
Microsoft BASIC and Wozmon. The source tree is scaffolded so implementation work
has a stable home and a shared vocabulary.

```text
configs/                 ld65 and build configuration files
docs/                    Clementina programmer and contributor docs
src/include/             shared ca65 include files and constants
src/kernel/              kernel entry, services, and public API
src/basic/               editable Microsoft BASIC fork
src/monitor/             monitor code and Wozmon import/port
src/utilities/           ROM-side utilities and demos
tools/                   build/import/check helper scripts
tests/                   emulator and binary-level tests
build/                   generated files, ignored by git
```

Start with [docs/index.md](docs/index.md).

## Toolchain

Use the cc65 suite:

- `ca65` for assembly
- `ld65` for linking
- `od65`, `da65`, and map/listing output when useful

This matches the current MIA demo kernel and the Microsoft BASIC source tree
used by both `mist64/msbasic` and Ben Eater's fork.

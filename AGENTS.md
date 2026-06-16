# Clementina ROM Agent Guide

This repository is the 6502-side system software for Clementina.

Before changing code, read:

1. `docs/index.md`
2. `docs/developer/agent-notes.md`
3. `docs/architecture.md`
4. `docs/memory-map.md`
5. `docs/mia-registers.md`

If working on Microsoft BASIC, also read `docs/basic.md`.

If working on Wozmon or monitor code, also read `docs/monitor.md`.

## Current Architecture

- MIA remains in high memory.
- Do not reintroduce the old bank-out-MIA/high-RAM idea unless the user
  explicitly asks for that architecture again.
- The initial kernel is loaded by MIA into CPU RAM at `$4000`.
- Use ca65 and ld65.
- Prefer kernel APIs over direct MIA access unless the task is specifically
  about low-level MIA behavior.

## External Context

MIA firmware:

- `/Users/fran150/development/pico/clementina-mia`

Go emulator:

- `/Users/fran150/development/go/clementina-6502`

Use firmware definitions as the source of truth for MIA registers, commands,
status bits, IRQ bits, fixed indexes, and MIA RAM layouts. Use the emulator to
verify CPU-visible behavior and memory decoding.

## Microsoft BASIC

Use `mist64/msbasic` as the clean upstream source and Ben Eater's fork as a
porting reference. `src/basic` is Clementina's editable BASIC fork. Edit the
source that assembles, keep upstream import/refresh commits easy to identify,
and use optional patches only for review or upstream submission.

## Monitor / Wozmon

Use `src/monitor` as Clementina's editable Wozmon import. Do not make build-time
patches the normal way to port it. Replace Apple 1 or serial I/O with kernel
services before wiring it into a Clementina image.

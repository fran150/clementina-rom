# Clementina ROM Agent Guide

This repository is the 6502-side system software for Clementina.

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

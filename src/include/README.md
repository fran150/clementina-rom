# src/include

`mia.inc` holds MIA's registers, status and IRQ bits, error codes, CFG field
ids, commands, index ids, index flag bits and MIA RAM layout for ca65, under
the names MIA's own C headers use. The kernel (through `kernel.inc`) and BASIC
include it; the Makefile puts this folder on every `ca65` include path.

The file is generated. clementina-sdk writes it from `specs/*.json` with
`npm run generate:includes`, and its `npm run check:drift` fails when this copy
differs from what the specs produce. To change a value:

1. Change the spec in clementina-sdk and run `npm run generate:includes`.
2. Copy clementina-sdk's `packages/runtime/asm/mia.inc` here.
3. Rebuild with `make` and check the image.

`IDX_FLAG_*` are bit numbers, as in MIA, so code writes
`(1 << IDX_FLAG_R_STP_ENA)`. Status and IRQ bits are 16-bit masks, so code
that reads `STATUS_H` uses the high byte, for example `>MIA_STAT_SD_BUSY`.
Multi-byte fields name each byte: `_L`/`_M`/`_H`, or `0`-`3` for 32-bit ones.

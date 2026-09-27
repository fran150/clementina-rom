# BASIC MIA memory access

These operations address MIA's **256 KiB internal RAM**, not the 6502's address
space or external banked RAM. Use ordinary `PEEK`/`POKE` for CPU addresses.

| Interface | Arguments | Meaning |
| --- | --- | --- |
| `MPEEK(address)` | address 0–262143 | Read one unsigned byte (0–255). |
| `MPOKE address,value` | address 0–262143; value 0–255 | Write one byte. |
| `MCOPY source,destination,length` | addresses 0–262143; length 0–262144 | Copy a block, preserving the original bytes when ranges overlap. |
| `MCOPY source,destination,length,rows,sourcestride,destinationstride` | length, rows and strides 0–65535 | Copy a rectangle: `rows` rows of `length` bytes, each starting `sourcestride` (`destinationstride`) bytes after the last. |
| `MFILL address,length,value` | address 0–262143; length 0–262144; value 0–255 | Fill a block with a repeated byte. |
| `MFILL address,length,value,rows,stride` | length, rows and stride 0–65535 | Fill a rectangle: `rows` rows of `length` bytes, each starting `stride` bytes after the last. |

Numeric expressions are accepted, including nested `MPEEK` calls. Fractions
truncate using BASIC's normal integer conversion. Negative values, out-of-range
arguments, and any block extending beyond address 262143 produce
`?ILLEGAL QUANTITY` before the operation writes anything. Expression side effects
are evaluated normally. A zero-length block does nothing, but its arguments
still must be valid. A same-address copy also does nothing after bounds checks.

```basic
10 MPOKE 131072,42
20 PRINT MPEEK(131072)
30 MFILL 131073,255,7
40 MCOPY 131072,131328,256
50 PRINT MPEEK(131328)
```

`MCOPY` has memmove semantics. For example, moving a block up by one byte
preserves its original contents instead of repeatedly copying its first byte:

```basic
10 MCOPY 131072,131073,100
```

### Rectangles

With `rows` and strides, `MCOPY` and `MFILL` work on a rectangle, such as a block
of a background map or of a 40-column table. This copies a 40×25 block out of a
1,024-byte-wide map at 98304 into a packed 40-byte-wide buffer, then clears an
8×4 area of it:

```basic
10 MCOPY 98304,65536,40,25,1024,40
20 MFILL 65536+2*40+16,8,0,4,40
```

- **Checked first.** The whole rectangle is checked before anything is written.
  A row longer than 65535 bytes, a stride over 65535, or a last row past address
  262143 gives `?ILLEGAL QUANTITY`. Zero rows or zero bytes per row do nothing.
- **No overlap in `MCOPY`.** The source and destination rectangles must not
  overlap: unlike the one-block form, the rectangle form copies each row
  forward, the way MIA's DMA does.

All addresses are raw MIA addresses. The video, input, audio, filesystem, and
clock regions retain their existing ownership and behavior: changing a byte does
not invoke a MIA command, and device-owned state can be overwritten by its owner.
Video writes and DMA copies use MIA's normal dirty-range tracking. The general
memory interface does not allocate or reserve storage for the program. Consult
the firmware memory layout when selecting a region for data.

## Implementation

No new MIA command or firmware protocol is required. The kernel uses the existing
`CMD_COPY_INDEXES` (`$10`) engine and reserved scratch descriptors `$F4`/`$F5`.
Each transfer sets an exclusive source limit and uses the existing zero command
count to mean `limit-current`. A real zero-length BASIC request never starts DMA.

Transfers larger than 65,535 bytes are split. Copy direction follows address
order, and each DMA chunk is capped at the distance between source and destination
so **every individual transfer has disjoint ranges**. This makes overlapping
moves safe on the Pico's forward-only DMA as well as the emulator. Very closely
overlapping ranges need many small chunks and can be slower than disjoint copies.

`MFILL` writes one seed byte, then copies initialized bytes into successive
regions, growing the copy size up to 65,535 bytes. Large fills require only a
small number of DMA commands; no 6502 byte-by-byte fill loop is used.

The rectangle forms use MIA's `COPY_RECT` command (`$11`) through the kernel
services `mia_mem_rect` and `mia_mem_fill_rect`.
- The two descriptors' steps hold the strides, and each command carries up to
  256 rows. Taller rectangles take several commands.
- `mia_mem_fill_rect` fills the first row as above, then repeats it with a
  source stride of 0.
- Inputs are `km_rows` and the 16-bit `km_sstride` and `km_dstride`, with
  `km_count` as the row length.

Commands are synchronous and wait for both command and DMA completion. Interrupts
remain available between descriptor updates and while waiting, so cursor blink
keeps ticking (background music, `docs/basic-sound.md`, runs entirely on MIA's
own sequencer and needs no 6502 interrupt to keep advancing regardless). Block
operations run to completion; they do not poll Ctrl-C partway through a copy or
fill.

Kernel link exports are `mia_mem_read`, `mia_mem_write`, `mia_mem_copy`,
`mia_mem_fill`, `mia_mem_rect`, and `mia_mem_fill_rect`, with little-endian
`km_src`, `km_dst`, `km_count`, `km_value`, `km_rows`, `km_sstride`, and
`km_dstride` arguments in the loaded image. Byte-service callers must supply validated
addresses; block services return C=1 on success or C=0 for invalid extents.
These foreground-only services clobber A/X/Y and window A's selection. Fixed
kernel entry addresses and BASIC's heap floor do not change. Existing token
numbers are preserved by appending the new keywords.

## Verification

Run:

```sh
python3 tests/run_input.py --run TestBasicMemory
```

The tests boot this ROM in the sibling emulator and cover nested expressions,
overlap in both directions, byte and 64 KiB boundaries, full-RAM filling,
zero-length/self copies, and range errors without partial writes. The test
runner also asserts that transfers through `$F4`/`$F5` never overlap: Go's
`copy` normally supports overlap and could otherwise hide a Pico DMA bug.

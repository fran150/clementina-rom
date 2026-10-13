# BASIC timing

| Interface | Meaning |
| --- | --- |
| `TICKS(0)` | Milliseconds since MIA's last runtime reset, modulo 4,294,967,296 (about 49.71 days). The argument must be zero. |
| `DELAY n` | Wait for `n` elapsed milliseconds, 0–65535. Fractions truncate; zero returns immediately. |
| `TI` | Numeric system clock in 1/60-second ticks, 0–5,183,999, wrapping every 24 hours. |
| `TI=n` / `LET TI=n` | Set that clock to 0–5,183,999 ticks; fractions truncate. `TI=0` starts an elapsed-time measurement. |

```basic
10 TI=0
20 DELAY 1000
30 PRINT "ELAPSED SECONDS:";TI/60
```

MIA's hardware timer provides the timebase. In the emulator it is elapsed
`StepContext.T` wall time. The clocks do not depend on PHI2 frequency, VIA
interrupt delivery, or the number of BASIC statements executed. TI continues
through READY, NEW, RUN, warm restart, and CPU pauses. A MIA runtime reset
resets both clocks. Setting TI restarts its fractional tick phase, but does not
reset TICKS or alter a running delay.

Reads take a command-latched snapshot, so multi-byte carries cannot produce a
torn time value. Values describe the time of that snapshot; BASIC execution and
I/O add latency. DELAY waits for elapsed whole milliseconds and may finish later
when the CPU is busy or slow. It handles the 32-bit millisecond wrap internally.

For elapsed time measured manually across a TICKS wrap:

```basic
10 A=TICKS(0)
20 DELAY 500
30 D=TICKS(0)-A
40 IF D<0 THEN D=D+4294967296
50 PRINT D
```

For TI elapsed time, similarly add 5,184,000 after a negative difference. Such
measurements assume no intervening clock assignment and less than one full
counter period between samples.

DELAY leaves interrupts enabled and polls BASIC's normal Ctrl-C check, so it
can still be interrupted with BREAK; that existing check also consumes
non-Ctrl-C queued text. Background music (`TRACK`/`BAND`, `docs/basic-sound.md`)
runs entirely on MIA's own sequencer and needs none of this to keep advancing
through DELAY - the 6502 isn't involved once it starts. Ctrl-C, `STOP`, `END`,
a runtime error, and `NEW` all still stop it, the same safety net the old
foreground/background `PLAY` had (now `seq_stop_all`, issuing `AUDIO_SEQ_STOP`
for every voice instead of clearing 6502-side player state). The kernel's VIA
Timer 1 tick (`KJIFFY`) still scales with CPU speed; BASIC no longer uses it.
It drives the cursor blink and stays available to machine code as a CPU-work
counter (`docs/memory-map.md` §2). The wall-time clock does not retime anything.

## TI variable semantics

TI is reserved as a numeric scalar. MS BASIC uses the first two significant
letters of a name, so TIME also names TI. Use LET or an ordinary assignment to
set it. Using it as FOR's loop variable or as a READ/INPUT/GET/device-output
variable is an illegal quantity error. `TI%`, `TI$`, and `TI(...)` remain ordinary
typed variables or arrays; **TI$ is not an HHMMSS clock interface in this phase**.

Existing saved programs retain their token numbers. Programs that previously
used a numeric scalar named TI (or a longer name starting with TI) must rename
that variable if it was not intended as a clock.

## MIA and kernel contract

Requires the companion firmware/emulator timing implementation. Both commands
run on MIA's normal command queue:

| Command | Parameters | Effect |
| --- | --- | --- |
| `$55` | all zero | Latch the clock snapshot below. |
| `$56` | p1/p2/p3 = low/middle/high | Set TI; values >= 5,184,000 are ignored. |

The formerly reserved tail of the input block, accessible with index `$60`:

| MIA RAM | Size | Contents |
| --- | --- | --- |
| `$11078` | 4 | Milliseconds, unsigned little-endian. |
| `$1107C` | 3 | TI ticks, unsigned little-endian. |
| `$1107F` | 1 | Snapshot protocol version, currently 1. |

The snapshot stays fixed until another `$55` command or runtime reset. This is
not a continuously updated memory counter. BASIC verifies the version before
using a snapshot, and reports an illegal quantity if clock support is absent.

The kernel side lives in `src/kernel/timing.s`. `timing_read` (also
`KERN_RDTIM`, `$0430`) copies the eight bytes to `CLOCK_SNAPSHOT`
(`$02F8–$02FF`) and returns C=1 when the version byte is 1. `timing_set` sends
the snapshot's three-byte 60 Hz slot with command `$56`; `KERN_SETTIM`
(`$0433`) takes the value in A/X/Y, stores it in that slot and falls into
`timing_set`. Both are foreground only. BASIC links to `timing_read`,
`timing_set` and `ktime_snapshot` directly; machine code uses the jump table
and reads `$02F8–$02FF` (`docs/memory-map.md` §4 and §6).

## Tests

`python3 tests/run_input.py --run TestBasicTiming` boots this checkout's ROM in
the sibling emulator. It checks TI reads/assignments, delay bounds, invalid
arguments, Ctrl-C, typed variables, and background music. The emulator's
`TestTimingClockProtocol` covers snapshots, CPU frequency independence, resets,
TI midnight, and the 32-bit millisecond rollover.

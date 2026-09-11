# Clementina BASIC — Sound

Clementina BASIC drives MIA's four‑voice PWM PSG with a small set of statements.
They are thin: each one writes MIA's audio registers and returns. There is no
background music player — you time note lengths yourself with `FOR`/`NEXT` or a
delay loop.

The chip model (waveforms, envelopes, the register block at `$12000`) is
described in the `clementina-mia` repo, `docs/audio.md`. This page is the BASIC
programmer's reference.

## Model

- **4 voices**, numbered **0–3** (like `COLOR`/`CRSR`, and like the hardware).
- Each voice has a frequency, a waveform, an ADSR envelope, a stereo pan, and a
  volume trim. A **gate** bit starts and releases the note.
- One **master volume** (0–15) scales everything.
- Audio starts **stopped**. Set your voices up, then `SNDON` once.

## Statements

| Statement | Arguments | Effect |
| --- | --- | --- |
| `SNDON` | — | Start the PSG (`AUDIO_ENABLE`). Do this once, after setting voices up. |
| `SNDOFF` | — | Stop the PSG. Voice registers are kept. |
| `SNDCLR` | — | Stop, clear every voice, and restore defaults. |
| `VOL n` | `n` 0–15 | Master volume. `0` mutes all output, `15` is full. |
| `VOL v,n` | `v` 0–3, `n` 0–255 | Voice `v` volume. `255` is unity; scales the whole voice (attack peaks included). |
| `WAVE v,w` | `w` 0–4 | Waveform: `0` sine, `1` pulse, `2` saw, `3` triangle, `4` noise. |
| `FREQ v,hz` | `hz` 0–4095 | Pitch in Hz. |
| `NOTE v,n` | `n` 0–95 | Pitch as a semitone number (see table). Gates the note on and retriggers it from the start of its waveform. |
| `GATE v,g` | `g` 0 or non‑zero | `g<>0` gates the note on (no retrigger); `g=0` releases it. |
| `ADSR v,a,d,s,r` | each 0–15 | Envelope. `a` attack rate, `d` decay rate, `s` sustain **level**, `r` release rate. Lower rate = faster. `s=0` silent, `s=15` full. |
| `PULSE v,pw` | `pw` 0–255 | Pulse duty. `128` ≈ square. Affects the pulse waveform only. |
| `PAN v,p` | `p` −64..63 | Stereo position. `-64` hard left, `0` centre, `63` hard right. |
| `PLAY s$` | music string | Play a sequence of notes described by `s$`. Blocks until the string finishes. See **PLAY** below. |
| `PLAY s$,n` | `n` background flag | `n<>0` plays `s$` in the **background** and returns immediately; `n=0` is the same as `PLAY s$`. See **Background PLAY** below. |
| `PLAY` | — | Stop the background player and silence its voices. |
| `PLAYING(0)` | — (function) | `1` while a background `PLAY` is still going, else `0`. The `(0)` is a required dummy argument. |

Out‑of‑range arguments raise `ILLEGAL QUANTITY`, exactly like `COLOR`.

`SNDON`/`SNDOFF`/`SNDCLR`, the ten command words above, `PLAY`, and `PLAYING`
are reserved — you cannot use them as variable names.

## Envelope, volume and gate

`ADSR` sets the note's shape; `SUSTAIN` is the level it holds at while gated.
`VOL v,n` is a separate trim on top of the envelope, so it can make a plucked or
percussive voice quiet, fade one voice, or balance the mix without disturbing
the envelope. The chain is:

```
oscillator -> ADSR envelope -> VOL v,n -> PAN -> mix -> VOL n (master) -> output
```

`NOTE` gates the voice on for you and restarts the waveform. `GATE v,1` gates on
**without** restarting (useful for legato / tied notes). `GATE v,0` releases:
the note fades out over its release time, it does not cut instantly.

## Semitone numbers (`NOTE`)

`NOTE` takes a number `0`–`95`. Number `= octave*12 + step`, where `step` is
`0 C, 1 C#, 2 D, 3 D#, 4 E, 5 F, 6 F#, 7 G, 8 G#, 9 A, 10 A#, 11 B`.

| Number | Note | | Number | Note |
| ---: | --- | --- | ---: | --- |
| 0 | C0 (≈16 Hz) | | 48 | C4 — middle C |
| 12 | C1 | | 57 | A4 — 440 Hz |
| 24 | C2 | | 60 | C5 |
| 36 | C3 | | 84 | C7 |
| 45 | A3 | | 95 | B7 (≈3950 Hz) |

Pitch is equal temperament, A4 = 440 Hz. The top octaves are a couple of cents
sharp (the table is built by doubling a rounded low‑octave value) — inaudible on
a PSG. For an exact frequency use `FREQ`.

## PLAY

`PLAY s$` plays a string of music commands. It **blocks** — the program stops at
the `PLAY` until the whole string has played. Set the voices up first (`SNDON`,
`WAVE`, `ADSR`, `PAN`, `VOL`); `PLAY` only writes the pitch and the gate.

```basic
10 SNDON : WAVE 0,1 : ADSR 0,0,8,12,7
20 PLAY "T80 L8 O4 C D E F G4 G4 A A A A G2 F F F F E2"
```

Commands in the string (letters are case‑insensitive; spaces and commas are just
separators):

| | Meaning |
| --- | --- |
| `A`–`G` | Play a note in the current octave. May be followed by `#` or `+` (sharp), `-` (flat), then length digits, then `.` (dotted = ×1.5). |
| `R`, `P` | Rest (silence) for one length. |
| `O n` | Set octave, `0`–`7`. |
| `<` `>` | Octave down / up (clamped to 0–7). |
| `L n` | Default note length: `1 2 4 8 16 32` = whole, half, quarter, eighth, 16th, 32nd. |
| `T n` | Tempo: **ticks per quarter note**, `1`–`255`. A tick is ≈ 1/160 s at 1 MHz PHI2 and scales with PHI2, so `T80` (the default) ≈ 120 BPM. |
| `V n` | Send the following notes to voice `n` (`0`–`3`). |
| `W n` | Set the current voice's waveform (`0`–`4`). |

Defaults at the start of every `PLAY`: voice 0, octave 4, `T80`, `L4`.

Every note re-triggers the current voice's envelope (a fresh attack), so
repeated notes and scales sound as distinct notes. A rest releases the note, and
the end of the string releases every voice. `PLAY` gives you the pitch and the
gate; the shape of each note is whatever `ADSR` you set for that voice — a short
decay/quick release for plucks, longer for pads.

**Limits.** `PLAY` is monophonic per voice and serial — `"V0 C E G V1 C"` plays
V0's three notes and *then* V1's note, not a chord. For chords, drive `NOTE`/`GATE`
from your own loop. Because `PLAY` blocks, it also swallows keystrokes while it
runs (except **Ctrl‑C**, which stops the music and returns to `READY`). An
unknown command raises `SYNTAX ERROR`; a bad number raises `ILLEGAL QUANTITY`;
either way every voice is silenced first.

## Background PLAY

`PLAY s$, n` (`n` any non‑zero value) plays `s$` **in the background** and
returns immediately — the rest of your program keeps running, including a
blocking `INPUT` or a tight `FOR/NEXT` loop, because the string is timed off
the same Timer‑1 interrupt as `KJIFFY`, not the foreground interpreter.

```basic
10 SNDON : WAVE 0,1 : ADSR 0,0,8,12,7
20 PLAY "T80 L8 O4 C D E F G4 G4 A A A A G2 F F F F E2",1
30 PRINT "the tune keeps playing while this runs"
40 INPUT "your name"; N$
```

- `PLAY s$` (no comma) and `PLAY s$,0` both still **block**, exactly as
  above — unchanged, back‑compatible.
- `PLAY` with **no argument at all** stops the background player and
  silences its voices.
- `PLAYING(0)` returns `1` while a background string is still playing, `0`
  once it finishes (or after you stop it). The `(0)` is a required dummy
  argument — every function in this BASIC is called as `NAME(expr)`, the same
  as classic `FRE(0)`; there is no bare/niladic function form.
- Starting a new background `PLAY` **replaces** whatever was already
  playing in the background (silencing it first — no orphaned notes).
- Ctrl‑C, `STOP`, `END`, `NEW`, and any runtime error all stop the
  background player too. `RUN` and `CLEAR` currently do **not** — a
  background tune from a previous run keeps playing across a `RUN` unless
  the new program itself issues a `PLAY`.
- A malformed background string (bad token or number) **does not** raise
  `SYNTAX ERROR`/`ILLEGAL QUANTITY` the way blocking `PLAY` does — it can't;
  the string is parsed one token at a time from inside an interrupt, and an
  interrupt can never safely enter BASIC's error handler. It just stops
  playing and silences its voice(s), silently. Get the string right with a
  blocking `PLAY` first if you're unsure.
- Only one background string plays at a time (monophonic per voice, serial,
  same as blocking `PLAY`). A voice driven by a background `PLAY` and by your
  own foreground `NOTE`/`FREQ`/`GATE` at the same time will fight each other —
  pick one owner per voice.

A scale, then the same idea split across two voices as call‑and‑response:

```basic
10 SNDON : WAVE 0,2 : WAVE 1,1 : ADSR 0,0,6,10,6 : ADSR 1,0,6,10,6
20 PLAY "T60 O4 C D E F G A B > C"
30 PLAY "T60 V0 O4 L8 C E G > C  V1 O5 L8 E G > C E"
```

## Examples

A plain beep — middle C for about a quarter second:

```basic
10 SNDON
20 WAVE 0,1 : ADSR 0,0,8,12,6
30 NOTE 0,48
40 FOR T=1 TO 400 : NEXT
50 GATE 0,0
```

A two‑voice arpeggio, panned apart:

```basic
10 SNDON : VOL 12
20 WAVE 0,2 : ADSR 0,0,6,8,7 : PAN 0,-40
30 WAVE 1,2 : ADSR 1,0,6,8,7 : PAN 1,40
40 FOR I=0 TO 23
50   V = I AND 1
60   NOTE V, 48 + 4*(I AND 3)
70   FOR T=1 TO 120 : NEXT
80 NEXT I
90 GATE 0,0 : GATE 1,0
```

A noise drum hit:

```basic
10 SNDON
20 WAVE 2,4 : FREQ 2,800 : ADSR 2,0,2,0,3 : VOL 2,220
30 GATE 2,1
40 FOR T=1 TO 30 : NEXT : GATE 2,0
```

Fade a held pad out with the master volume:

```basic
10 SNDON
20 WAVE 3,0 : ADSR 3,10,8,14,10 : NOTE 3,36
30 FOR V=15 TO 0 STEP -1 : VOL V : FOR T=1 TO 200 : NEXT : NEXT
40 SNDOFF
```

## Notes and limits

- `FREQ` tops out just under 4096 Hz. `NOTE` above about `95` exceeds that and
  errors.
- `PAN` centre is a few dB quieter than hard‑panned (it is a linear balance, not
  constant power).
- Changing `WAVE`, `ADSR`, `PAN`, `VOL`, `PULSE` or `FREQ` on a sounding voice
  takes effect immediately; you do not need to re‑gate.
- After `SNDCLR` every voice is back to: pulse wave, pulse width 128, envelope
  `SUSTAIN_RELEASE` `$F5`, centre pan, volume 255; master volume 15.
- `PLAY` timing comes from the kernel tick (`KJIFFY`), which runs off the VIA
  Timer 1 IRQ. It is roughly 1/160 s at 1 MHz PHI2 and follows PHI2, so a `PLAY`
  string plays faster at a higher clock. `PLAY` blocks and does not need
  `SNDON`‑style re‑enabling per note, but you still need `SNDON` once.

# Clementina BASIC — Sound

Clementina BASIC drives MIA's four‑voice PWM PSG with a small set of statements.
Most are thin: each one writes MIA's audio registers and returns. Background
music is the exception — it runs entirely on MIA's own sequencer (see
**Background sequencer** below), not a 6502-side interpreter, so once you
start it, it costs the 6502 nothing.

The chip model (waveforms, envelopes, the register block at `$12000`) is
described in the `clementina-mia` repo, `docs/audio.md`; the sequencer
bytecode `TRACK` compiles to is in that repo's `docs/audio-sequencer.md`.
This page is the BASIC programmer's reference.

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
| `TRACK v,s$[,addr%]` | music string, optional MIA RAM address | Compile `s$` into voice `v`'s independent background-sequencer part. `addr%` places it anywhere in MIA RAM instead of the default per-voice slot; a track has no length limit to outgrow. See **Background sequencer** below. |
| `BAND n` | `n` 0 or 1 | Master switch: `1` starts every voice with a loaded track, `0` stops all four. |
| `BAND v,n` | `v` 0–3, `n` 0 or 1 | Per-voice on/off, same `n` meaning. |
| `VTAKE v` | `v` 0–3 | Freeze voice `v`'s track (without silencing it) so you can drive it directly. |
| `VGIVE v` | `v` 0–3 | Release voice `v` back to its track. |
| `PLAYING(v)` | `v` 0–3 (function) | `1` while voice `v` has an active background track, else `0`. |
| `CUE(v)` | `v` 0–3 (function) | Voice `v`'s current note/rest index in its track (1-based; `0` = not started). |

Out‑of‑range arguments raise `ILLEGAL QUANTITY`, exactly like `COLOR`.

`SNDON`/`SNDOFF`/`SNDCLR`, the twelve command words above, and `PLAYING`/`CUE`
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

## Background sequencer

`TRACK v,s$` compiles a music string into voice `v`'s own part and writes it
straight into MIA RAM; `BAND` starts and stops playback. From the moment
`BAND` runs, MIA plays every assigned voice on its own — nothing here costs
the 6502 anything, unlike a 6502-side player that has to keep parsing and
timing a string itself.

```basic
10 SNDON : WAVE 0,1 : ADSR 0,0,8,12,7
20 TRACK 0,"T80 L8 O4 C D E F G4 G4 A A A A G2 F F F F E2"
30 BAND 1
```

Set the voice up first (`SNDON`, `WAVE`, `ADSR`, `PAN`, `VOL`) — `TRACK`'s
string only ever drives pitch, gate, and (via `W n`) waveform.

`TRACK`'s string is the same mini-language as before, minus voice-switching
(each `TRACK` call is already scoped to one voice) and plus `|` for a loop
point (letters are case‑insensitive; spaces and commas are just separators):

| | Meaning |
| --- | --- |
| `A`–`G` | A note in the current octave. May be followed by `#` or `+` (sharp), `-` (flat), then length digits, then `.` (dotted = ×1.5). |
| `R`, `P` | Rest (silence) for one length. |
| `O n` | Set octave, `0`–`7`. |
| `<` `>` | Octave down / up (clamped to 0–7). |
| `L n` | Default note length: `1 2 4 8 16 32` = whole, half, quarter, eighth, 16th, 32nd. |
| `T n` | Tempo: **ticks per quarter note**, `1`–`255`. A tick is a fixed 1/160 s (`T80`, the default, ≈ 120 BPM) — resolved once when `TRACK` compiles the string, so playback speed never depends on the CPU's clock speed, unlike the old foreground/background `PLAY`. |
| `W n` | Set the current voice's waveform (`0`–`4`). |
| `\|` | Mark the loop point: everything before it plays once (an intro); everything from it to the end of the string repeats forever once `BAND` starts this voice. No `\|` means the whole string plays once and stops. |

Defaults at the start of every `TRACK` string: octave 4, `T80`, `L4`.

An unknown token raises `SYNTAX ERROR`; a bad number raises `ILLEGAL
QUANTITY`. Either way nothing is silenced — `TRACK` only ever writes into
MIA RAM, it never touches a live register, so a mistake here can't leave a
stray note sounding.

### `BAND`, `VTAKE`/`VGIVE`, and mixing music with sound effects

- `BAND 1` starts every voice that has a loaded track and isn't already
  running; `BAND 0` stops and silences all four, whichever way they were
  started. `BAND v,n` does the same for one voice.
- Starting a voice (fresh `TRACK`, or `BAND`/`BAND v,1` after a stop) always
  begins at the top of its track. Stopping (`BAND 0`/`BAND v,0`) freezes that
  voice's position rather than resetting it, so starting it again resumes
  exactly where it left off.
- `VTAKE v` freezes voice `v`'s track **without** silencing it — the note it
  was on keeps sounding until your own `NOTE`/`GATE`/`FREQ`/etc. writes land.
  `VGIVE v` hands it back, catching up to wherever the track would be if it
  had kept running the whole time (not just resuming where it paused) — so a
  brief effect on a voice doesn't leave that voice permanently behind the
  others.
- `PLAYING(v)` and `CUE(v)` are safe to poll in a tight loop — they read
  straight from MIA RAM, no command round-trip.

A two-voice loop, with an explosion sound effect stealing the bass voice for
a moment:

```basic
10 SNDON
20 WAVE 0,1 : ADSR 0,0,8,12,7 : TRACK 0,"T80 L8 O4 C D E F | G4 G4 A A A A G2 F F F F E2"
30 WAVE 1,2 : ADSR 1,0,6,10,6 : TRACK 1,"T80 L4 O2 C G | C G C G C G"
40 BAND 1
50 REM ... game loop runs here while both voices loop forever ...
100 VTAKE 1
110 WAVE 1,4 : ADSR 1,0,2,0,3 : NOTE 1,24
120 FOR T=1 TO 20 : NEXT
130 VGIVE 1
```

### Timing a change with `CUE`

`CUE(v)` reports how many notes and rests voice `v` has played since its
track was last loaded (1-based; `0` before it starts). It keeps counting
across a `|` loop rather than resetting each pass — the loop point compiles
to a `JUMP`, which (like any jump) doesn't reset the count, so `CUE` is really
a running total, not "position within this pass." That's exactly what a
one-time wait for a specific transition wants:

```basic
10 SNDON : WAVE 0,1 : ADSR 0,0,6,10,6 : TRACK 0,"T80 L4 O4 C D E F | G A B > C"
20 BAND 0,1
30 IF CUE(0) <> 4 THEN 30      : REM wait for the start of the loop body
40 WAVE 1,1 : ADSR 1,0,6,10,6 : TRACK 1,"T80 L4 O3 C G"
50 BAND 1,1
```

This waits correctly because `CUE(0)` only ever equals `4` once — the moment
the 5th note (the loop body's first, `G`) starts, `CUE` becomes `5` and never
returns to `4`. To check *repeatedly* for "the start of each pass" instead
(not just the first), compute it yourself from the body's length, e.g.
`(CUE(0)-4) MOD 4 = 1` for a 4-note body starting at index 5.

Loading a new `TRACK` for a voice that's currently muted (`BAND v,0`) always
starts that voice at the top the next time it's turned back on — so watching
`CUE` on a voice that's still running, then swapping a *different*, currently
stopped voice's `TRACK` and turning it on at the right moment, is how you
change a melody in sync with the rest of the band.

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

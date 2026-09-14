# BASIC input

Input is independent of text: `GET A$` consumes the text FIFO; held-key and
controller queries do not. Numeric arguments use BASIC's usual integer
conversion. Invalid ranges produce an error.

| Statement/function | Meaning |
| --- | --- |
| `INPUTMODE n` | Select console (0), Wi-Fi (1), or USB host (2). Errors if unavailable; clears BASIC's input snapshots on success. |
| `INPUTDEV(0)` | Live capability mask: keyboard 1, consumer 2, mouse 4; connected gamepads 0–3 use bits 3–6. Console provides text only. |
| `KEYDOWN(code)` | 1 if keyboard HID usage 0–255 is held, otherwise 0. |
| `CONSDOWN(code)` | Same query for consumer-page HID usage 0–255. |
| `KEYCLEAR` | Discard the currently queued text bytes, leaving held state intact. |
| `KEYREPEAT delay,interval` | MIA repeat timing in milliseconds, both 1–65535. Defaults: 400,60. Changing timing cancels the active repeat; press the key again. |
| `KEYREPEAT 0` | Disable MIA-generated repeat. |
| `KEYRPT code,enabled` | Configure eligibility for keyboard usage 0–255; enabled is 0 or 1. |
| `MOUSE DX,DY,B,W,P` | Read relative X/Y motion, buttons, vertical wheel and horizontal pan into numeric variables (float, integer, or array elements). |
| `PADREAD n` | Sample gamepad slot 0–3. Queries below use that cached sample, initially zero. |
| `PADON(n)` | 1 if the sampled pad is connected, otherwise 0. |
| `PADDIR(n)` | D-pad bits: up 1, down 2, left 4, right 8. |
| `PADSTICK(n)` | Digital stick directions: left up/down/left/right in bits 0–3, right in bits 4–7. |
| `PADBTN(n,b)` | Button bit 0–15 as 0 or 1. |
| `PADAXIS(n,a)` | Axes 0–3: left X/Y, right X/Y; −128…127. Negative X is left; negative Y is up. |
| `PADTRIG(n,t)` | Triggers 0 (left), 1 (right), 0–255. |

Button numbers follow MIA: 0 A/Cross, 1 B/Circle, 2 C/right paddle,
3 X/Square, 4 Y/Triangle, 5 Z/left paddle, 6 L1, 7 R1, 8 L2, 9 R2,
10 Select/Back, 11 Start/Menu, 12 Home, 13 L3, 14 R3; 15 is reserved.

```basic
10 PADREAD 0
20 IF PADON(0)=0 THEN 10
30 X=X+PADAXIS(0,0)/32
40 IF KEYDOWN(80) THEN X=X-1
50 IF KEYDOWN(79) THEN X=X+1
60 SPRX 0,X
70 GOTO 10
```

Mouse buttons are left 1, right 2, middle 4, back 8, forward 16. The first
sample establishes a baseline and returns zero motion. An observed change in
source or mouse availability resets that baseline. MIA publishes availability
rather than a session generation number: disconnect/reconnect entirely between
polls cannot be detected. `INPUTMODE` also resets the baseline.

Motion uses MIA's wrapping 8-bit accumulators. Poll often enough that each
accumulated delta remains within −128…127. Larger movements between polls are
ambiguous. Mouse and gamepad reads are sequential, not atomic hardware snapshots.
A `PADREAD` gives subsequent queries a stable copy of those ten bytes.

Repeat defaults cover arrows, Backspace and Delete. Settings live in MIA and
reset with MIA runtime reset. Only events with a decoded text byte can repeat;
enabling a modifier does not generate text. `KEYREPEAT 0` does not filter
client-generated text packets or terminal repeat. Console/USB source availability
depends on the MIA build; USB HID decoding remains a firmware integration task.

## Implementation and compatibility

Requires the companion MIA firmware/emulator repeat-command changes:

| Command | Parameters (third byte always zero) |
| --- | --- |
| `$52` | delay milliseconds, little-endian p1/p2; zero disables |
| `$53` | interval milliseconds, little-endian p1/p2; zero ignored |
| `$54` | p1 keyboard usage, p2 enable 0/1; invalid enable ignored |

No existing token numbers or fixed kernel jump-table addresses change. The kernel
exports `input_read_byte` (A = block offset, returns A, preserves X/Y),
`input_clear_text`, and `input_command` (A = command, X/Y = parameters 1/2) for
linked clients. These are link symbols, not new fixed-address ABI entries.
Indexed reads explicitly seek within `$11000–$1107F`; they use window A with
interrupts briefly masked so cursor IRQs cannot reposition it mid-read.
BASIC's mouse baseline and gamepad cache occupy initialized bytes in the loaded
image and are cleared on BASIC cold start. They do not move the heap floor.

## Verification

Run `python3 tests/run_input.py` to build this ROM and boot it in the sibling
emulator without installing the image. Use `--emulator /path/to/clementina-6502`
for another checkout. The emulator must include the companion repeat commands.

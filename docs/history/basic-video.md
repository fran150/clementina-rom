# BASIC video statements history

How the background, sprite, CHR and palette statements were added. The current
reference is [../basic-video.md](../basic-video.md).

## Phases

- **Phase 1 (2026-09-11).** Layer toggles, `BGMODE`/`BGSET`/`SCROLL`, CHR bank
  selection (`BGBANK`/`BGALT`/`SPRBANK`), `SPRCOUNT`, `CHRMODE`/`CHRPLANE`,
  `PALETTE` and `VIDON`/`VIDOFF`. All direct register wrappers; the index wiring
  already existed in the firmware and the emulator. Tests:
  `basic_video_phase1_test.go` in clementina-6502.
- **Phase 2a (2026-09-11), reduced.** Only `OAMLOAD` and `SPRITE` fit under the
  ROM's 16 KiB code ceiling of the time, with no bytes to spare; `BGLOAD`,
  `CHRLOAD`, `PALLOAD`, `BGCHAR` and the single-field sprite setters were cut.
  Tests: `basic_video_phase2_test.go`.
- **Phase 2b (2026-09-12).** Everything cut from 2a came back after the code
  ceiling was raised by 2 KiB ([memory-map.md](memory-map.md), "The code
  budget"): `BGLOAD`, `CHRLOAD`, `PALLOAD`, a new `BGCHAR`, and
  `SPRX`/`SPRY`/`SPRTILE`/`SPRCOLOR`/`SPRFLIP`/`SPRPRI`. Tests:
  `basic_video_phase2b_test.go`, covering every `BGMODE` branch of `BGCHAR`,
  `BGLOAD`'s two parallel streams, and that each single-field sprite setter
  touches only its own bits.
- **File I/O rename (2026-09).** `BGLOAD`, which wrote both halves of a
  background table in one interleaved call, was split into `NTREAD` and
  `ATRREAD`; `CHRLOAD`/`PALLOAD`/`OAMLOAD` became `CHRREAD`/`PALREAD`/`OAMREAD`
  for their DATA-sourced behaviour. The bare `*LOAD` names were then reused for
  loading from an SD file, with matching `*SAVE` statements
  ([../basic-file.md](../basic-file.md)).
- **OAM count units (2026-09-16).** After the rename, `OAMLOAD`/`OAMSAVE`
  counted bytes while `OAMREAD` counted sprites (5-byte records). Every other
  family has a stride of 1, where the two agree, so only OAM showed it. The
  docs already promised sprites, so `oam_count_x5` now multiplies the count by
  5 before the SD command.
- **Path first (2026-10-17, G12).** The ten file statements take the path
  first, loads take the whole file, and a save's count is optional. They used
  to take the path last with a required count, as in
  `CHRLOAD 1,100,3,"FONT.BIN"`.

## How the `*READ` statements read `DATA`

`vid_data_byte` (`clementina_extra.s`) advances `DATPTR` and pulls one numeric
item the way `READ` does, then writes it to an auto-incrementing MIA address,
without the interpreter overhead of a `FOR...READ...POKE...NEXT` loop. It
borrows the real `READ` statement: it points `TXTPTR` at the name of a scratch
variable, `Z9`, and calls `READ`, so `Z9` gets the next `DATA` value and
`DATPTR` advances exactly as a real `READ` would (a real `?OUT OF DATA` error
included). Then it evaluates `Z9` again with `GETBYT` to get a byte. `Z9`'s
value is saved and restored around each statement.

Phase 2b found two bugs in the dual-stream (`VID_ADDR`/`VID_ADDR2`) code that
`BGLOAD` needed, both about `Y`:

- `vid_wr_abs` carried its stream selector in `Y`, clobbering the loop
  counters of callers that expected `Y` to survive (`SPRITE`'s write loop and
  `vid_bulk_run`'s field loop). It now uses a scratch byte.
- `READ` and `GETBYT` use `Y` freely, so `Y` does not survive `vid_data_byte`,
  and `vid_bulk_run` read its field index from `Y` after that call. Every
  single-stream statement hid it, because the stream decision came out as
  `0 AND anything`; only `BGLOAD`, the one multi-stream user, exposed it. The
  index now lives in `VID_FIELD` and is loaded into `Y` right before the one
  instruction that needs it.

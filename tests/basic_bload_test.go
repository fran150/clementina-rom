package clementina

import (
	"os"
	"path/filepath"
	"testing"
)

// writePRG writes a PRG file (2-byte addr, +1 bank byte if addr is banked,
// then the payload) into dir/name, per docs/basic-file.md.
func writePRG(t *testing.T, dir, name string, addr uint16, bank byte, payload []byte) {
	t.Helper()
	data := []byte{byte(addr), byte(addr >> 8)}
	if addr >= 0x8000 {
		data = append(data, bank)
	}
	data = append(data, payload...)
	if err := os.WriteFile(filepath.Join(dir, name), data, 0644); err != nil {
		t.Fatal(err)
	}
}

// TestBasicBLOADSwallowWithRun loads a tiny machine-code program over BASIC's
// heap with a run address, and confirms it actually starts executing instead
// of returning to BASIC.
func TestBasicBLOADSwallowWithRun(t *testing.T) {
	dir := t.TempDir()
	// LDA #$2A / STA $0280 / LDA #$99 / STA $0281 / JMP <self>, loaded+run at $6000.
	prg := []byte{0xA9, 0x2A, 0x8D, 0x80, 0x02, 0xA9, 0x99, 0x8D, 0x81, 0x02, 0x4C, 0x0A, 0x60}
	writePRG(t, dir, "T.PRG", 0x6000, 0, prg)

	c, step := bootClementinaToPrompt(t)
	c.SetMiaSDFolder(dir)
	typeLine(c, step, `10 BLOAD "T.PRG",$6000`)
	typeLine(c, step, "RUN")
	editorTickN(c, step, 1_000_000)

	require_eq(t, 0x2A, peek(c, 0x0280), "swallow-load program ran (first POKE)")
	require_eq(t, 0x99, peek(c, 0x0281), "swallow-load program ran (second POKE)")
}

// TestBasicBLOADAboveLoweredMemsiz reserves $B000-$BFFF by lowering MEMSIZ,
// BLOADs a routine there from a bank-0 PRG without a run address, calls it
// with SYS and checks that BASIC carries on: strings still work after the
// load, so bank 0 is mapped again.
func TestBasicBLOADAboveLoweredMemsiz(t *testing.T) {
	dir := t.TempDir()
	// LDA #$2A / STA $0280 / RTS, loaded at $B000 bank 0.
	writePRG(t, dir, "R.PRG", 0xB000, 0, []byte{0xA9, 0x2A, 0x8D, 0x80, 0x02, 0x60})

	c, step := bootClementinaToPrompt(t)
	c.SetMiaSDFolder(dir)
	for _, l := range []string{
		"10 POKE 63,0:POKE 64,176:CLEAR", // MEMSIZ = $B000
		`20 BLOAD "R.PRG"`,
		"30 SYS 45056",
		`40 A$="OK"+"!":POKE 641,LEN(A$)`,
		"50 POKE 642,PEEK(64)",
		"60 GOTO 60",
	} {
		typeLine(c, step, l)
	}
	typeLine(c, step, "RUN")
	editorTickN(c, step, 1_000_000)

	require_eq(t, 0x2A, peek(c, 0x0280), "routine loaded above MEMSIZ ran")
	require_eq(t, 3, peek(c, 641), "strings work after the load")
	require_eq(t, 0xB0, peek(c, 642), "MEMSIZ stayed lowered")
}

// TestBasicBLOADOverrideIntoMappedBank overrides an unbanked file's address
// with one in $8000-$BFFF: it lands in the mapped bank (bank 0 under BASIC)
// and BLOAD returns.
func TestBasicBLOADOverrideIntoMappedBank(t *testing.T) {
	dir := t.TempDir()
	writePRG(t, dir, "D.PRG", 0x6000, 0, []byte{7, 8})

	c, step := bootClementinaToPrompt(t)
	c.SetMiaSDFolder(dir)
	for _, l := range []string{
		"10 POKE 63,0:POKE 64,176:CLEAR",
		`20 BLOAD "D.PRG",0,45056`, // no run, address $B000
		"30 POKE 640,PEEK(45056)",
		"40 POKE 641,PEEK(45057)",
		"50 POKE 642,PEEK(24576)", // $6000, the header's address, untouched
		"60 POKE 643,42",
		"70 GOTO 70",
	} {
		typeLine(c, step, l)
	}
	typeLine(c, step, "RUN")
	editorTickN(c, step, 1_000_000)

	require_eq(t, 42, peek(c, 643), "BASIC resumed after the load")
	require_eq(t, 7, peek(c, 640), "first byte at the override address")
	require_eq(t, 8, peek(c, 641), "second byte at the override address")
	if peek(c, 642) == 7 {
		t.Fatal("the header's address was written instead of the override")
	}
}

// TestBasicBLOADOverrideOfBankedFile overrides a banked file's address with
// an unbanked one: the header's bank byte is skipped, not loaded as data.
func TestBasicBLOADOverrideOfBankedFile(t *testing.T) {
	dir := t.TempDir()
	writePRG(t, dir, "K.PRG", 0x8000, 3, []byte{9, 10})

	c, step := bootClementinaToPrompt(t)
	c.SetMiaSDFolder(dir)
	for _, l := range []string{
		`10 BLOAD "K.PRG",0,640`, // no run, address $0280
		"20 POKE 642,42",
		"30 GOTO 30",
	} {
		typeLine(c, step, l)
	}
	typeLine(c, step, "RUN")
	editorTickN(c, step, 1_000_000)

	require_eq(t, 42, peek(c, 642), "BASIC resumed after the load")
	require_eq(t, 9, peek(c, 640), "first payload byte at the override address")
	require_eq(t, 10, peek(c, 641), "second payload byte at the override address")
}

// TestBasicBLOADBankedAutoAdvance loads a 16-byte payload starting 8 bytes before
// the top of a bank, confirming it auto-advances into the next bank instead
// of requiring the caller to chunk across banks itself, and that an ordinary
// (non-swallow) banked BLOAD returns to BASIC normally.
func TestBasicBLOADBankedAutoAdvance(t *testing.T) {
	dir := t.TempDir()
	payload := []byte{1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16}
	writePRG(t, dir, "B.PRG", 0xBFF8, 5, payload)

	c, step := bootClementinaToPrompt(t)
	c.SetMiaSDFolder(dir)

	for _, l := range []string{
		`10 BLOAD "B.PRG"`,
		"20 POKE 49153,5",
		"30 POKE 640,PEEK(49144)", // $BFF8, first byte -> 1
		"40 POKE 641,PEEK(49151)", // $BFFF, last byte of bank 5 -> 8
		"50 POKE 49153,6",
		"60 POKE 642,PEEK(32768)", // $8000, first byte of bank 6 -> 9
		"70 POKE 643,PEEK(32775)", // $8007, last byte of payload -> 16
		"80 POKE 49153,0",
		"90 POKE 644,42",
		"100 GOTO 100",
	} {
		typeLine(c, step, l)
	}
	typeLine(c, step, "RUN")
	editorTickN(c, step, 1_000_000)

	require_eq(t, 42, peek(c, 644), "BASIC resumed normally after an ordinary banked BLOAD")
	require_eq(t, 1, peek(c, 640), "bank 5 first byte")
	require_eq(t, 8, peek(c, 641), "bank 5 last byte")
	require_eq(t, 9, peek(c, 642), "auto-advanced into bank 6, first byte")
	require_eq(t, 16, peek(c, 643), "bank 6, last payload byte")
}

// TestBasicBSAVEUnbankedRoundTrip writes a small unbanked blob with BSAVE and
// confirms the file on disk carries the matching 2-byte header and payload.
func TestBasicBSAVEUnbankedRoundTrip(t *testing.T) {
	dir := t.TempDir()
	c, step := bootClementinaToPrompt(t)
	c.SetMiaSDFolder(dir)

	for _, l := range []string{
		"10 FOR I=0 TO 15",
		"20 POKE 24576+I,I+1",
		"30 NEXT I",
		`40 BSAVE "S.PRG",24576,16`,
		"50 POKE 700,42",
		"60 GOTO 60",
	} {
		typeLine(c, step, l)
	}
	typeLine(c, step, "RUN")
	editorTickN(c, step, 1_000_000)

	require_eq(t, 42, peek(c, 700), "BASIC resumed normally after an unbanked BSAVE")

	data, err := os.ReadFile(filepath.Join(dir, "S.PRG"))
	if err != nil {
		t.Fatal(err)
	}
	want := []byte{0x00, 0x60, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16}
	if string(data) != string(want) {
		t.Fatalf("S.PRG = % X, want % X", data, want)
	}
}

// TestBasicBSAVEBankedRoundTrip round-trips a payload that spans a bank
// boundary through BLOAD then BSAVE, and confirms the re-saved file is
// byte-identical to the original - exercising BSAVE's own auto-advance
// against real (BLOAD-written) banked data instead of freshly-POKEd bytes.
func TestBasicBSAVEBankedRoundTrip(t *testing.T) {
	dir := t.TempDir()
	payload := []byte{1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16}
	writePRG(t, dir, "B.PRG", 0xBFF8, 5, payload)

	c, step := bootClementinaToPrompt(t)
	c.SetMiaSDFolder(dir)

	for _, l := range []string{
		`10 BLOAD "B.PRG"`,
		`20 BSAVE "C.PRG",49144,16,5`, // 49144 = $BFF8
		"30 POKE 700,42",
		"40 GOTO 40",
	} {
		typeLine(c, step, l)
	}
	typeLine(c, step, "RUN")
	editorTickN(c, step, 1_000_000)

	require_eq(t, 42, peek(c, 700), "BASIC resumed normally after a banked BSAVE")

	original, err := os.ReadFile(filepath.Join(dir, "B.PRG"))
	if err != nil {
		t.Fatal(err)
	}
	roundTripped, err := os.ReadFile(filepath.Join(dir, "C.PRG"))
	if err != nil {
		t.Fatal(err)
	}
	if string(original) != string(roundTripped) {
		t.Fatalf("C.PRG = % X, want (= B.PRG) % X", roundTripped, original)
	}
}

// TestBasicBSAVEWithoutBankPinsMappedBank saves from $8000 while bank 3 is
// mapped: without a bank argument the file records bank 3, with one it
// records that bank, and either way BSAVE maps bank 3 back afterwards.
func TestBasicBSAVEWithoutBankPinsMappedBank(t *testing.T) {
	dir := t.TempDir()
	c, step := bootClementinaToPrompt(t)
	c.SetMiaSDFolder(dir)

	for _, l := range []string{
		"10 POKE 49153,3", // map bank 3; no strings until bank 0 is back
		"20 FOR I=0 TO 3:POKE 32768+I,I+1:NEXT I",
		`30 BSAVE "P.PRG",32768,4`,
		`40 BSAVE "Q.PRG",32768,4,5`,
		"50 POKE 700,PEEK(49153) AND 31",
		"60 POKE 49153,0",
		"70 POKE 701,42",
		"80 GOTO 80",
	} {
		typeLine(c, step, l)
	}
	typeLine(c, step, "RUN")
	editorTickN(c, step, 1_000_000)

	require_eq(t, 42, peek(c, 701), "BASIC resumed after the saves")
	require_eq(t, 3, peek(c, 700), "BSAVE mapped bank 3 back")
	for name, want := range map[string][]byte{
		"P.PRG": {0x00, 0x80, 3, 1, 2, 3, 4},
		"Q.PRG": {0x00, 0x80, 5},
	} {
		data, err := os.ReadFile(filepath.Join(dir, name))
		if err != nil {
			t.Fatal(err)
		}
		if string(data[:len(want)]) != string(want) {
			t.Fatalf("%s = % X, want it to start % X", name, data, want)
		}
	}
}

// TestBasicBSAVEBankZero saves from bank 0 above a lowered MEMSIZ with an
// explicit bank 0.
func TestBasicBSAVEBankZero(t *testing.T) {
	dir := t.TempDir()
	c, step := bootClementinaToPrompt(t)
	c.SetMiaSDFolder(dir)

	for _, l := range []string{
		"10 POKE 63,0:POKE 64,176:CLEAR", // MEMSIZ = $B000
		"20 POKE 45056,7:POKE 45057,8",
		`30 BSAVE "Z.PRG",45056,2,0`,
		"40 POKE 700,42",
		"50 GOTO 50",
	} {
		typeLine(c, step, l)
	}
	typeLine(c, step, "RUN")
	editorTickN(c, step, 1_000_000)

	require_eq(t, 42, peek(c, 700), "BASIC resumed after the save")
	data, err := os.ReadFile(filepath.Join(dir, "Z.PRG"))
	if err != nil {
		t.Fatal(err)
	}
	want := []byte{0x00, 0xB0, 0, 7, 8}
	if string(data) != string(want) {
		t.Fatalf("Z.PRG = % X, want % X", data, want)
	}
}

// TestBasicBSAVEBankOutOfRangeErrors confirms a bank above 31 is rejected
// before any file is created.
func TestBasicBSAVEBankOutOfRangeErrors(t *testing.T) {
	dir := t.TempDir()
	c, step := bootClementinaToPrompt(t)
	c.SetMiaSDFolder(dir)

	for _, l := range []string{
		`10 BSAVE "X.PRG",32768,16,32`,
		"20 POKE 700,42",
		"30 GOTO 30",
	} {
		typeLine(c, step, l)
	}
	typeLine(c, step, "RUN")
	editorTickN(c, step, 1_000_000)

	require_eq(t, 0, peek(c, 700), "line 20 never ran - BSAVE was rejected")
	if _, err := os.Stat(filepath.Join(dir, "X.PRG")); err == nil {
		t.Fatal("X.PRG should not have been created")
	}
}

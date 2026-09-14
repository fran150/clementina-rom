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

// TestBasicBLOADSwallowWithRun loads a tiny machine-code program into the
// reclaimable heap region (>= KERN_BASE, unbanked) with a run address, and
// confirms it actually starts executing instead of returning to BASIC.
func TestBasicBLOADSwallowWithRun(t *testing.T) {
	dir := t.TempDir()
	// LDA #$2A / STA $0200 / LDA #$99 / STA $0201 / JMP <self>, loaded+run at $6000.
	prg := []byte{0xA9, 0x2A, 0x8D, 0x00, 0x02, 0xA9, 0x99, 0x8D, 0x01, 0x02, 0x4C, 0x0A, 0x60}
	writePRG(t, dir, "T.PRG", 0x6000, 0, prg)

	c, step := bootClementinaToPrompt(t)
	c.SetMiaSDFolder(dir)
	typeLine(c, step, `10 BLOAD "T.PRG",$6000`)
	typeLine(c, step, "RUN")
	editorTickN(c, step, 1_000_000)

	require_eq(t, 0x2A, peek(c, 0x0200), "swallow-load program ran (first POKE)")
	require_eq(t, 0x99, peek(c, 0x0201), "swallow-load program ran (second POKE)")
}

// TestBasicBLOADSwallowWithoutRunErrors confirms the same load, without a run
// address, is rejected before writing anything - the program never reaches
// its next statement.
func TestBasicBLOADSwallowWithoutRunErrors(t *testing.T) {
	dir := t.TempDir()
	prg := []byte{0xA9, 0x2A, 0x8D, 0x00, 0x02, 0x4C, 0x05, 0x60}
	writePRG(t, dir, "T.PRG", 0x6000, 0, prg)

	c, step := bootClementinaToPrompt(t)
	c.SetMiaSDFolder(dir)
	typeLine(c, step, `10 BLOAD "T.PRG"`)
	typeLine(c, step, "20 POKE 512,42")
	typeLine(c, step, "30 GOTO 30")
	typeLine(c, step, "RUN")
	editorTickN(c, step, 1_000_000)

	require_eq(t, 0, peek(c, 512), "line 20 never ran - BLOAD was rejected before writing")
	require_eq(t, 0, peek(c, 0x0200), "destination untouched - rejected before writing")
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
		"30 POKE 512,PEEK(49144)", // $BFF8, first byte -> 1
		"40 POKE 513,PEEK(49151)", // $BFFF, last byte of bank 5 -> 8
		"50 POKE 49153,6",
		"60 POKE 514,PEEK(32768)", // $8000, first byte of bank 6 -> 9
		"70 POKE 515,PEEK(32775)", // $8007, last byte of payload -> 16
		"80 POKE 49153,0",
		"90 POKE 516,42",
		"100 GOTO 100",
	} {
		typeLine(c, step, l)
	}
	typeLine(c, step, "RUN")
	editorTickN(c, step, 1_000_000)

	require_eq(t, 42, peek(c, 516), "BASIC resumed normally after an ordinary banked BLOAD")
	require_eq(t, 1, peek(c, 512), "bank 5 first byte")
	require_eq(t, 8, peek(c, 513), "bank 5 last byte")
	require_eq(t, 9, peek(c, 514), "auto-advanced into bank 6, first byte")
	require_eq(t, 16, peek(c, 515), "bank 6, last payload byte")
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

// TestBasicBSAVEBankedWithoutBankErrors confirms a banked destination
// without an explicit bank argument is rejected rather than silently saving
// whatever bank happens to be currently selected.
func TestBasicBSAVEBankedWithoutBankErrors(t *testing.T) {
	dir := t.TempDir()
	c, step := bootClementinaToPrompt(t)
	c.SetMiaSDFolder(dir)

	for _, l := range []string{
		`10 BSAVE "X.PRG",32768,16`,
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

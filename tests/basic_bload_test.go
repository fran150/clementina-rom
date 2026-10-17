package clementina

import (
	"os"
	"path/filepath"
	"testing"
)

// writePRG writes a PRG file (2-byte load address, then the payload) into
// dir/name, per docs/basic-file.md.
func writePRG(t *testing.T, dir, name string, addr uint16, payload []byte) {
	t.Helper()
	data := append([]byte{byte(addr), byte(addr >> 8)}, payload...)
	if err := os.WriteFile(filepath.Join(dir, name), data, 0644); err != nil {
		t.Fatal(err)
	}
}

// peekBank reads addr ($8000-$BFFF) in a given bank, whichever is mapped.
func peekBank(c *ClementinaComputer, addr uint16, bank uint8) uint8 {
	portA := c.mappers.portA.MapFromSource([]uint8{bank & 0x1F})
	low := c.mappers.exRam.MapFromSource([]uint16{addr, portA})
	high := c.mappers.exRamHi.MapFromSource([]uint16{portA})
	return c.chips.exram.Peek(uint32(low) | uint32(high)<<16)
}

// TestBasicBRUNJumpsToFirstByte loads a tiny machine-code program over
// BASIC's heap with BRUN and no run address: it starts at the first byte
// loaded instead of returning to BASIC.
func TestBasicBRUNJumpsToFirstByte(t *testing.T) {
	dir := t.TempDir()
	// LDA #$2A / STA $0280 / LDA #$99 / STA $0281 / JMP <self>, at $6000.
	prg := []byte{0xA9, 0x2A, 0x8D, 0x80, 0x02, 0xA9, 0x99, 0x8D, 0x81, 0x02, 0x4C, 0x0A, 0x60}
	writePRG(t, dir, "T.PRG", 0x6000, prg)

	c, step := bootClementinaToPrompt(t)
	c.SetMiaSDFolder(dir)
	typeLine(c, step, `10 BRUN "T.PRG"`)
	typeLine(c, step, "20 POKE 642,42")
	typeLine(c, step, "RUN")
	editorTickN(c, step, 1_000_000)

	require_eq(t, 0x2A, peek(c, 0x0280), "the program ran (first POKE)")
	require_eq(t, 0x99, peek(c, 0x0281), "the program ran (second POKE)")
	require_eq(t, 0, peek(c, 642), "BRUN never returned to BASIC")
}

// TestBasicBRUNRunAddress jumps to a run address inside the payload, not to
// its first byte.
func TestBasicBRUNRunAddress(t *testing.T) {
	dir := t.TempDir()
	prg := []byte{
		0xA9, 0x11, 0x8D, 0x80, 0x02, 0x4C, 0x05, 0x60, // $6000: LDA #$11 / STA $0280 / JMP $6005
		0xA9, 0x2A, 0x8D, 0x80, 0x02, 0x4C, 0x0D, 0x60, // $6008: LDA #$2A / STA $0280 / JMP $600D
	}
	writePRG(t, dir, "T.PRG", 0x6000, prg)

	c, step := bootClementinaToPrompt(t)
	c.SetMiaSDFolder(dir)
	typeLine(c, step, `10 BRUN "T.PRG",$6008`)
	typeLine(c, step, "RUN")
	editorTickN(c, step, 1_000_000)

	require_eq(t, 0x2A, peek(c, 0x0280), "BRUN jumped to the run address")
}

// TestBasicBRUNInBank loads a program into bank 2 at $8000 with BANK 2 and
// runs it there: the code sits in bank 2 and runs with bank 2 mapped.
func TestBasicBRUNInBank(t *testing.T) {
	dir := t.TempDir()
	// LDA #$2A / STA $0280 / LDA $C001 / AND #$1F / STA $0281 / JMP <self>
	prg := []byte{0xA9, 0x2A, 0x8D, 0x80, 0x02, 0xAD, 0x01, 0xC0, 0x29, 0x1F, 0x8D, 0x81, 0x02, 0x4C, 0x0D, 0x80}
	writePRG(t, dir, "R.PRG", 0x8000, prg)

	c, step := bootClementinaToPrompt(t)
	c.SetMiaSDFolder(dir)
	typeLine(c, step, `10 BANK 2:BRUN "R.PRG"`)
	typeLine(c, step, "RUN")
	editorTickN(c, step, 1_000_000)

	require_eq(t, 0x2A, peek(c, 0x0280), "the program in bank 2 ran")
	require_eq(t, 2, peek(c, 0x0281), "it ran with bank 2 mapped")
	require_eq(t, 0xA9, peekBank(c, 0x8000, 2), "the code was loaded into bank 2")
}

// TestBasicBLOADAboveLoweredMemsiz reserves $B000-$BFFF by lowering MEMSIZ,
// BLOADs a routine there, calls it with SYS and checks that BASIC carries
// on: strings still work after the load, so bank 0 is mapped again.
func TestBasicBLOADAboveLoweredMemsiz(t *testing.T) {
	dir := t.TempDir()
	// LDA #$2A / STA $0280 / RTS, loaded at $B000.
	writePRG(t, dir, "R.PRG", 0xB000, []byte{0xA9, 0x2A, 0x8D, 0x80, 0x02, 0x60})

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

// TestBasicBLOADOverrideAddress loads a file at an address given in the
// command instead of its header's, and BLOAD returns.
func TestBasicBLOADOverrideAddress(t *testing.T) {
	dir := t.TempDir()
	writePRG(t, dir, "D.PRG", 0x6000, []byte{7, 8})

	c, step := bootClementinaToPrompt(t)
	c.SetMiaSDFolder(dir)
	for _, l := range []string{
		"10 POKE 63,0:POKE 64,176:CLEAR",
		`20 BLOAD "D.PRG",45056`, // $B000
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

// TestBasicBLOADOldRunFormRejected checks the old BLOAD path,run,addr form
// gives SYNTAX ERROR before loading anything.
func TestBasicBLOADOldRunFormRejected(t *testing.T) {
	dir := t.TempDir()
	writePRG(t, dir, "K.PRG", 0x6000, []byte{9, 10})

	c, step := bootClementinaToPrompt(t)
	c.SetMiaSDFolder(dir)
	for _, l := range []string{
		`10 BLOAD "K.PRG",0,640`,
		"20 POKE 642,42",
		"30 GOTO 30",
	} {
		typeLine(c, step, l)
	}
	typeLine(c, step, "RUN")
	editorTickN(c, step, 1_000_000)

	require_eq(t, 0, peek(c, 642), "line 20 never ran")
	require_eq(t, 0, peek(c, 640), "nothing was loaded at $0280")
	if _, ok := screenContainsRow(c.chips.mia.(videoReader), "?SYNTAX ERROR"); !ok {
		t.Fatal("no SYNTAX ERROR on screen")
	}
}

// TestBasicBLOADBankedAutoAdvance loads a 16-byte payload starting 8 bytes
// before the top of bank 5 (BANK 5), confirming it auto-advances into bank 6
// instead of requiring the caller to chunk across banks itself, that PEEK
// reads the BANK bank, and that bank 0 is mapped again afterwards.
func TestBasicBLOADBankedAutoAdvance(t *testing.T) {
	dir := t.TempDir()
	payload := []byte{1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16}
	writePRG(t, dir, "B.PRG", 0xBFF8, payload)

	c, step := bootClementinaToPrompt(t)
	c.SetMiaSDFolder(dir)

	for _, l := range []string{
		`10 BANK 5:BLOAD "B.PRG"`,
		"20 POKE 645,PEEK(49153) AND 31", // bank 0 is mapped again
		"30 POKE 640,PEEK(49144)",        // $BFF8, first byte -> 1
		"40 POKE 641,PEEK(49151)",        // $BFFF, last byte of bank 5 -> 8
		"50 BANK 6",
		"60 POKE 642,PEEK(32768)", // $8000, first byte of bank 6 -> 9
		"70 POKE 643,PEEK(32775)", // $8007, last byte of payload -> 16
		"80 BANK 0",
		`90 A$="OK"+"!":POKE 644,LEN(A$)`,
		"100 GOTO 100",
	} {
		typeLine(c, step, l)
	}
	typeLine(c, step, "RUN")
	editorTickN(c, step, 1_000_000)

	require_eq(t, 3, peek(c, 644), "BASIC resumed normally, strings work")
	require_eq(t, 0, peek(c, 645), "bank 0 mapped after BLOAD")
	require_eq(t, 1, peek(c, 640), "bank 5 first byte")
	require_eq(t, 8, peek(c, 641), "bank 5 last byte")
	require_eq(t, 9, peek(c, 642), "auto-advanced into bank 6, first byte")
	require_eq(t, 16, peek(c, 643), "bank 6, last payload byte")
	require_eq(t, 1, peekBank(c, 0xBFF8, 5), "bank 5 holds the first byte")
	require_eq(t, 16, peekBank(c, 0x8007, 6), "bank 6 holds the last byte")
}

// TestBasicBANKPokePeek checks POKE and PEEK at $8000-$BFFF use the BANK bank
// and map bank 0 back, so strings keep working in between.
func TestBasicBANKPokePeek(t *testing.T) {
	c, step := bootClementinaToPrompt(t)
	for _, l := range []string{
		"10 BANK 3:POKE 32768,9:POKE 640,PEEK(49153) AND 31",
		`20 A$="X"+"YZ":POKE 641,LEN(A$)`,
		"30 POKE 642,PEEK(32768)",
		"40 BANK 4:POKE 643,PEEK(32768):BANK 0",
		"50 POKE 644,42",
		"60 GOTO 60",
	} {
		typeLine(c, step, l)
	}
	typeLine(c, step, "RUN")
	editorTickN(c, step, 1_000_000)

	require_eq(t, 42, peek(c, 644), "the program ran to the end")
	require_eq(t, 0, peek(c, 640), "bank 0 mapped again after POKE")
	require_eq(t, 3, peek(c, 641), "strings work with BANK 3 picked")
	require_eq(t, 9, peek(c, 642), "PEEK reads bank 3")
	require_eq(t, 9, peekBank(c, 0x8000, 3), "POKE wrote bank 3")
	if peek(c, 643) == 9 {
		t.Fatal("PEEK with BANK 4 read bank 3")
	}
}

// TestBasicBANKOutOfRange checks BANK 32 gives ILLEGAL QUANTITY.
func TestBasicBANKOutOfRange(t *testing.T) {
	c, step := bootClementinaToPrompt(t)
	typeLine(c, step, "10 BANK 32")
	typeLine(c, step, "20 POKE 640,42")
	typeLine(c, step, "RUN")
	editorTickN(c, step, 500_000)

	require_eq(t, 0, peek(c, 640), "line 20 never ran")
	if _, ok := screenContainsRow(c.chips.mia.(videoReader), "?ILLEGAL QUANTITY"); !ok {
		t.Fatal("no ILLEGAL QUANTITY on screen")
	}
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
	writePRG(t, dir, "B.PRG", 0xBFF8, payload)

	c, step := bootClementinaToPrompt(t)
	c.SetMiaSDFolder(dir)

	for _, l := range []string{
		`10 BANK 5:BLOAD "B.PRG"`,
		`20 BSAVE "C.PRG",49144,16`, // 49144 = $BFF8
		"30 POKE 700,42",
		"40 POKE 701,PEEK(49153) AND 31",
		"50 GOTO 50",
	} {
		typeLine(c, step, l)
	}
	typeLine(c, step, "RUN")
	editorTickN(c, step, 1_000_000)

	require_eq(t, 42, peek(c, 700), "BASIC resumed normally after a banked BSAVE")
	require_eq(t, 0, peek(c, 701), "bank 0 mapped after BSAVE")

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

// TestBasicBSAVEFromBank saves from $8000 with BANK 3 picked: the bytes come
// from bank 3 and the header holds only the address.
func TestBasicBSAVEFromBank(t *testing.T) {
	dir := t.TempDir()
	c, step := bootClementinaToPrompt(t)
	c.SetMiaSDFolder(dir)

	for _, l := range []string{
		"10 BANK 3:FOR I=0 TO 3:POKE 32768+I,I+1:NEXT I",
		`20 BSAVE "P.PRG",32768,4`,
		"30 BANK 0:POKE 700,42",
		"40 GOTO 40",
	} {
		typeLine(c, step, l)
	}
	typeLine(c, step, "RUN")
	editorTickN(c, step, 1_000_000)

	require_eq(t, 42, peek(c, 700), "BASIC resumed after the save")
	data, err := os.ReadFile(filepath.Join(dir, "P.PRG"))
	if err != nil {
		t.Fatal(err)
	}
	want := []byte{0x00, 0x80, 1, 2, 3, 4}
	if string(data) != string(want) {
		t.Fatalf("P.PRG = % X, want % X", data, want)
	}
}

// TestBasicBSAVEOldBankFormRejected confirms the old trailing bank argument
// gives SYNTAX ERROR before any file is created.
func TestBasicBSAVEOldBankFormRejected(t *testing.T) {
	dir := t.TempDir()
	c, step := bootClementinaToPrompt(t)
	c.SetMiaSDFolder(dir)

	for _, l := range []string{
		`10 BSAVE "X.PRG",32768,16,5`,
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

package clementina

// Checkpoints use $0280 (640), above both line buffers in the $0200 page
// (BASIC's ends at $0252, WozMon's at $027F), so typed lines never touch them.
// Do not use heap addresses: stored programs can grow through them.

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestBasicFSExtensionsUpdateAndQueries(t *testing.T) {
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "A"), []byte("ABCDE"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "B"), []byte("xyz"), 0600); err != nil {
		t.Fatal(err)
	}
	c, step := bootClementinaToPrompt(t)
	c.SetMiaSDFolder(dir)
	lines := []string{
		`10 OPEN "A" FOR UPDATE AS #1`,
		`20 OPEN "B" FOR INPUT AS #2`,
		`30 BGET#2,V`,
		`40 SEEK#1,FPOS(2)`,
		`50 BPUT#1,65+FSIZE(2)`,
		`60 FLUSH #1`,
		`70 POKE 640,FPOS(1)`,
		`80 POKE 641,FSIZE(1)`,
		`90 POKE 642,FPOS(2)`,
		`100 POKE 643,FSIZE(2)`,
		`110 BGET#1,V:POKE 644,V`,
		`120 CLOSE #1:CLOSE #2`,
		`130 OPEN "C" FOR UPDATE AS #3`,
		`140 POKE 645,FSIZE(3)`,
		`150 BPUT#3,99:CLOSE #3`,
		`160 POKE 646,42`,
		`170 GOTO 170`,
	}
	for _, l := range lines {
		typeLine(c, step, l)
	}
	typeLine(c, step, "RUN")
	editorTickN(c, step, 2_000_000)
	for i, v := range []int{2, 5, 1, 3, 67, 0, 42} {
		if int(peek(c, uint32(640+i))) != v {
			dumpScreen(t, c.chips.mia.(videoReader))
		}
		require_eq(t, v, peek(c, uint32(640+i)), fmt.Sprint("query ", i))
	}
	data, err := os.ReadFile(filepath.Join(dir, "A"))
	if err != nil {
		t.Fatal(err)
	}
	if string(data) != "ADCDE" {
		t.Fatalf("update = %q", data)
	}
	data, err = os.ReadFile(filepath.Join(dir, "B"))
	if err != nil || string(data) != "xyz" {
		t.Fatalf("other handle changed: %q %v", data, err)
	}
	data, err = os.ReadFile(filepath.Join(dir, "C"))
	if err != nil || string(data) != "c" {
		t.Fatalf("new file: %q %v", data, err)
	}
}

func TestBasicFSExtensionsMetadataAndFree(t *testing.T) {
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "A"), make([]byte, 257), 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.Mkdir(filepath.Join(dir, "D"), 0700); err != nil {
		t.Fatal(err)
	}
	c, step := bootClementinaToPrompt(t)
	c.SetMiaSDFolder(dir)
	for _, l := range []string{
		`10 DIM Z(3)`,
		`20 FSTAT "A",S,A,D,T`,
		`30 IF S=257 THEN POKE 640,1`,
		`40 IF D>0 THEN POKE 641,1`,
		`50 FSTAT "D",Z(0),Z(1),Z(2),Z(3)`,
		`60 POKE 642,Z(1) AND 16`,
		`70 F=DISKFREE(0)`,
		`80 IF F=1073709056 THEN POKE 643,1`,
		`90 POKE 644,42`,
		`100 GOTO 100`,
	} {
		typeLine(c, step, l)
	}
	typeLine(c, step, "RUN")
	editorTickN(c, step, 2_000_000)
	for i, v := range []int{1, 1, 16, 1, 42} {
		if int(peek(c, uint32(640+i))) != v {
			dumpScreen(t, c.chips.mia.(videoReader))
		}
		require_eq(t, v, peek(c, uint32(640+i)), fmt.Sprint("metadata ", i))
	}
}

func TestBasicFSExtensionsSeek32(t *testing.T) {
	dir := t.TempDir()
	// Sparse fixture avoids allocating or writing several GiB.
	f, err := os.Create(filepath.Join(dir, "BIG"))
	if err != nil {
		t.Fatal(err)
	}
	if err = f.Truncate(4294967295); err != nil {
		f.Close()
		t.Fatal(err)
	}
	f.Close()
	c, step := bootClementinaToPrompt(t)
	c.SetMiaSDFolder(dir)
	for _, l := range []string{
		`10 OPEN "BIG" FOR INPUT AS #1`,
		`20 N=4294967295`,
		`30 IF FSIZE(1)=N THEN POKE 640,1`,
		`40 SEEK#1,2147483648`,
		`50 P=FPOS(1)`,
		`60 IF P=2147483648 THEN POKE 641,1`,
		`70 SEEK#1,N`,
		`80 IF FPOS(1)=N THEN POKE 642,1`,
		`90 SEEK#1,16777217.9`,
		`100 P=FPOS(1)`,
		`110 IF P=16777217 THEN POKE 643,1`,
		`120 CLOSE #1`,
		`130 POKE 644,42`,
		`140 GOTO 140`,
	} {
		typeLine(c, step, l)
	}
	typeLine(c, step, "RUN")
	editorTickN(c, step, 2_000_000)
	for i, v := range []int{1, 1, 1, 1, 42} {
		if int(peek(c, uint32(640+i))) != v {
			dumpScreen(t, c.chips.mia.(videoReader))
		}
		require_eq(t, v, peek(c, uint32(640+i)), fmt.Sprint("32-bit seek ", i))
	}
}

func TestBasicFSExtensionsErrors(t *testing.T) {
	for _, tc := range []struct{ line, err string }{
		{"FLUSH #0", "ILLEGAL QUANTITY"},
		{"PRINT FPOS(0)", "ILLEGAL QUANTITY"},
		{"PRINT FSIZE(-1)", "ILLEGAL QUANTITY"},
		{"MPOKE 77824,5:PRINT FPOS(1)", "FILE I/O ERROR"}, {"FLUSH #1", "FILE I/O ERROR"},
		{"PRINT FPOS(1)", "FILE I/O ERROR"}, {"PRINT FSIZE(17)", "ILLEGAL QUANTITY"},
		{`FSTAT "MISSING",S,A,D,T`, "FILE I/O ERROR"},
		{"PRINT DISKFREE(1)", "ILLEGAL QUANTITY"},
		{"SEEK#1,-1", "ILLEGAL QUANTITY"}, {"SEEK#1,4294967296", "ILLEGAL QUANTITY"},
	} {
		t.Run(tc.line, func(t *testing.T) {
			c, step := bootClementinaToPrompt(t)
			c.SetMiaSDFolder(t.TempDir())
			typeLine(c, step, tc.line)
			vr := c.chips.mia.(videoReader)
			var screen strings.Builder
			for row := 0; row < 25; row++ {
				for col := 0; col < 40; col++ {
					screen.WriteByte(ntCell(vr, row, col))
				}
			}
			if !strings.Contains(screen.String(), tc.err) {
				dumpScreen(t, vr)
				t.Fatalf("missing %s", tc.err)
			}
		})
	}
}

// MIALOAD loads a whole file at a 24-bit address, including files over
// 65535 bytes; the old length, offset and rectangle arguments give SYNTAX
// ERROR before anything loads. MIASAVE takes a 24-bit length.
func TestBasicMialoadWholeFile(t *testing.T) {
	dir := t.TempDir()
	grid := make([]byte, 160)
	for i := range grid {
		grid[i] = byte(i)
	}
	big := make([]byte, 70000)
	for i := range big {
		big[i] = byte(i % 251)
	}
	for name, data := range map[string][]byte{"MAP.BIN": grid, "BIG.BIN": big} {
		if err := os.WriteFile(filepath.Join(dir, name), data, 0o644); err != nil {
			t.Fatal(err)
		}
	}
	c, step := bootClementinaToPrompt(t)
	c.SetMiaSDFolder(dir)
	vr := c.chips.mia.(videoReader)
	for _, line := range []string{
		`10 MIALOAD "MAP.BIN",$31A78`, // 203384
		`20 MIALOAD "BIG.BIN",100000`,
		`30 MIASAVE "OUT.BIN",100000,70000`,
		`40 POKE 640,42`,
		`50 MIALOAD "MAP.BIN",200000,20`,
		`60 POKE 641,42`, `70 GOTO 70`,
	} {
		typeLine(c, step, line)
	}
	typeLine(c, step, "RUN")
	editorTickN(c, step, 3_000_000)
	require_eq(t, 42, peek(c, 640), "MIALOAD and MIASAVE ran")
	require_eq(t, 0, peek(c, 641), "the old length form stopped the program")
	if _, ok := screenContainsRow(vr, "?SYNTAX ERROR"); !ok {
		dumpScreen(t, vr)
		t.Fatal("no SYNTAX ERROR for the old length form")
	}
	require_eq(t, 0, vr.DebugReadVideo(200000), "the old length form loaded nothing")
	require_eq(t, 0, vr.DebugReadVideo(203384), "first byte of the whole-file load")
	require_eq(t, 159, vr.DebugReadVideo(203384+159), "last byte of the whole-file load")
	require_eq(t, 69999%251, vr.DebugReadVideo(100000+69999), "last byte of a 70000-byte load")
	out, err := os.ReadFile(filepath.Join(dir, "OUT.BIN"))
	if err != nil {
		t.Fatal(err)
	}
	if string(out) != string(big) {
		t.Fatalf("OUT.BIN is %d bytes, want the 70000 loaded", len(out))
	}
}

// TestBasicOpenAppend opens a file FOR APPEND. The tokenizer stores the END
// inside APPEND as the END token, which OPEN's word match used to reject with
// SYNTAX ERROR.
func TestBasicOpenAppend(t *testing.T) {
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "LOG"), []byte("A"), 0600); err != nil {
		t.Fatal(err)
	}
	c, step := bootClementinaToPrompt(t)
	c.SetMiaSDFolder(dir)
	typeLine(c, step, `10 OPEN "LOG" FOR APPEND AS #1`)
	typeLine(c, step, `20 BPUT#1,66:CLOSE #1:POKE 640,42`)
	typeLine(c, step, `30 GOTO 30`)
	typeLine(c, step, "RUN")
	editorTickN(c, step, 1_000_000)
	require_eq(t, 42, peek(c, 640), "program ran past OPEN")
	data, err := os.ReadFile(filepath.Join(dir, "LOG"))
	if err != nil || string(data) != "AB" {
		t.Fatalf("appended file = %q %v", data, err)
	}
}

// fsRowAfter fails unless the first non-blank screen row after the one reading
// `line` reads `want` (both trimmed). READY. always follows a blank row: its
// message starts with CR, LF.
func fsRowAfter(t *testing.T, c *ClementinaComputer, line, want string) {
	t.Helper()
	for row := 0; row < 24; row++ {
		if strings.TrimRight(printScreenRow(c, row), " \x00") == line {
			got := ""
			for next := row + 1; next < 25 && got == ""; next++ {
				got = strings.TrimRight(printScreenRow(c, next), " \x00")
			}
			if got != want {
				dumpScreen(t, c.chips.mia.(videoReader))
				t.Fatalf("after %q: want %q got %q", line, want, got)
			}
			return
		}
	}
	dumpScreen(t, c.chips.mia.(videoReader))
	t.Fatalf("no row reads %q", line)
}

// TestBasicLoadEndsAtReady checks LOAD prints READY, typed directly and when a
// program runs it (that program stops there). LOAD used to jump into the input
// loop past READY, so nothing was printed.
func TestBasicLoadEndsAtReady(t *testing.T) {
	c, step := bootClementinaToPrompt(t)
	c.SetMiaSDFolder(t.TempDir())
	typeLine(c, step, `10 PRINT 1`)
	typeLine(c, step, `SAVE "P"`)
	typeLine(c, step, "CLS")
	typeLine(c, step, `LOAD "P"`)
	editorTickN(c, step, 400_000)
	fsRowAfter(t, c, `LOAD "P"`, "READY.")

	typeLine(c, step, `10 PRINT "A":LOAD "P"`)
	typeLine(c, step, `20 PRINT "B"`)
	typeLine(c, step, "CLS")
	typeLine(c, step, "RUN")
	editorTickN(c, step, 800_000)
	fsRowAfter(t, c, "RUN", "A")
	fsRowAfter(t, c, "A", "READY.")
	typeLine(c, step, "CLS")
	typeLine(c, step, "LIST")
	fsRowAfter(t, c, "LIST", " 10 PRINT 1")
}

// TestBasicBgetPastEndReadsZero reads a 2-byte file four times. Past the end
// BGET# stores 0 and EOF turns 1, with no error; it used to repeat the last
// byte, which was still in MIA's transfer buffer.
func TestBasicBgetPastEndReadsZero(t *testing.T) {
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "F"), []byte("XY"), 0600); err != nil {
		t.Fatal(err)
	}
	c, step := bootClementinaToPrompt(t)
	c.SetMiaSDFolder(dir)
	typeLine(c, step, `10 OPEN "F" FOR INPUT AS #1`)
	typeLine(c, step, `20 FOR I=0 TO 3:BGET#1,V:POKE 640+I,V:POKE 644+I,EOF(1):NEXT`)
	typeLine(c, step, `30 CLOSE #1:POKE 648,42`)
	typeLine(c, step, `40 GOTO 40`)
	typeLine(c, step, "RUN")
	editorTickN(c, step, 2_000_000)
	for i, v := range []int{88, 89, 0, 0, 0, 1, 1, 1, 42} {
		require_eq(t, v, peek(c, uint32(640+i)), fmt.Sprint("checkpoint ", i))
	}
}

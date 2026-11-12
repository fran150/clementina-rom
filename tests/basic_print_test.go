package clementina

import (
	"strings"
	"testing"
)

// printScreenRow returns one 40-column row of the text nametable.
func printScreenRow(c *ClementinaComputer, row int) string {
	vr := c.chips.mia.(videoReader)
	b := make([]byte, 40)
	for i := range b {
		b[i] = vr.DebugReadVideo(uint32(0x10080 + row*40 + i))
	}
	return string(b)
}

// TestBasicPrintColumnAfterNewline checks BASIC's output column (POS, TAB and
// comma zones) restarts at 0 after every line end: a PRINT's own newline, the
// end of INPUT, and a CR printed from inside a string. It used to stay at 13,
// the CR code CRDO stores there.
func TestBasicPrintColumnAfterNewline(t *testing.T) {
	c, step := bootClementinaToPrompt(t)
	typeLine(c, step, `10 PRINT "AB":POKE 640,POS(0)`)
	typeLine(c, step, `20 PRINT "AB";:POKE 641,POS(0):PRINT`)
	typeLine(c, step, `30 PRINT "AB";CHR$(13);"CD";:POKE 642,POS(0):PRINT`)
	typeLine(c, step, `40 INPUT A:POKE 643,POS(0)`)
	typeLine(c, step, "50 GOTO 50")
	typeLine(c, step, "RUN")
	typeLine(c, step, "7")
	editorTickN(c, step, 500_000)

	require_eq(t, 0, peek(c, 640), "column after PRINT's newline")
	require_eq(t, 2, peek(c, 641), "column after two characters")
	require_eq(t, 2, peek(c, 642), "column after a CR inside a string")
	require_eq(t, 0, peek(c, 643), "column after INPUT")
}

// TestBasicPrintTabAndZones checks TAB and comma zones land on their columns
// on a line that follows a newline.
func TestBasicPrintTabAndZones(t *testing.T) {
	c, step := bootClementinaToPrompt(t)
	typeLine(c, step, `10 CLS:PRINT:PRINT TAB(5);"X":PRINT TAB(20);"Y":PRINT "A","B","C"`)
	typeLine(c, step, "20 GOTO 20")
	typeLine(c, step, "RUN")
	editorTickN(c, step, 500_000)

	for _, want := range []struct {
		row, col int
		text     string
	}{{1, 5, "X"}, {2, 20, "Y"}, {3, 0, "A"}, {3, 14, "B"}, {3, 28, "C"}} {
		row := printScreenRow(c, want.row)
		if got := strings.Index(row, want.text); got != want.col {
			t.Fatalf("%q at column %d of row %d, want %d: %q", want.text, got, want.row, want.col, row)
		}
	}
}

// TestBasicBootBanner checks the cold-start screen: the slanted flag logo (sky
// blue, white, sky blue rows of reverse spaces ending in a triangle) with the
// title and copyright lines beside it, then a blank line and READY. No BYTES
// FREE line and no second Microsoft notice.
func TestBasicBootBanner(t *testing.T) {
	c, _ := bootClementinaToPrompt(t)
	vr := c.chips.mia.(videoReader)
	attr := func(row, col int) int { return int(vr.DebugReadVideo(uint32(0x10468 + row*40 + col))) }

	flag := func(cells int) string { return " " + strings.Repeat(" ", cells) + "\xa1" }
	want := []string{
		"",
		flag(7) + "  CLEMENTINA V1.0 BASIC V2",
		flag(6) + "   \x9e 2026 PACHISOFT",
		flag(5) + "    \x9e 1977 MICROSOFT BASIC",
		"",
		"READY.",
	}
	for row, line := range want {
		got := strings.TrimRight(printScreenRow(c, row), " \x00")
		if got != line {
			t.Fatalf("row %d = %q, want %q", row, got, line)
		}
	}
	const alt = 0x80 // CHR_ALT: the reversed bank, so a space is a solid cell
	bands := []struct{ row, cells, pen int }{{1, 7, 0x05}, {2, 6, 0x00}, {3, 5, 0x05}}
	for _, b := range bands {
		for col := 1; col <= b.cells; col++ {
			if got := attr(b.row, col); got != b.pen|alt {
				t.Fatalf("flag cell (%d,%d) attr = $%02X, want $%02X", b.row, col, got, b.pen|alt)
			}
		}
		if got := attr(b.row, b.cells+1); got != b.pen {
			t.Fatalf("slant cell (%d,%d) attr = $%02X, want $%02X", b.row, b.cells+1, got, b.pen)
		}
		if got := attr(b.row, 12); got != 0 {
			t.Fatalf("text cell (%d,12) attr = $%02X, want $00", b.row, got)
		}
	}
}

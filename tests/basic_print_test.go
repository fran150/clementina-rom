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

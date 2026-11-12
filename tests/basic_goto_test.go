package clementina

import "testing"

// TestBasicGotoForwardPastSidecar jumps forward from a line that holds a
// string literal to a line in a higher 256-line block. GOTO then searches from
// the byte after the current line's $00, where such a line keeps its style
// sidecar ($CE $FF ...); without stepping past it, GOTO read the sidecar as the
// next line's header and stopped with ?UNDEF'D STATEMENT ERROR.
func TestBasicGotoForwardPastSidecar(t *testing.T) {
	for _, tc := range []struct{ line10, target string }{
		{`10 IF "L"="L" THEN 255`, "255"}, // same block: searched from the start
		{`10 IF "L"="L" THEN 256`, "256"},
		{`10 A$="L":IF A$="L" THEN 300`, "300"},
		{`10 PRINT "HI":GOTO 300`, "300"},
		{`10 PRINT "HI":GOSUB 300:END`, "300"},
	} {
		c, step := bootClementinaToPrompt(t)
		typeLine(c, step, tc.line10)
		typeLine(c, step, `20 POKE 640,2:END`)
		typeLine(c, step, tc.target+` PRINT "X":POKE 640,1:END`)
		typeLine(c, step, "RUN")
		editorTickN(c, step, 800_000)

		require_eq(t, 1, peek(c, 640), tc.line10+" reached line "+tc.target)
	}
}

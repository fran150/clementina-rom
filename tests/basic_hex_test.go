package clementina

import (
	"strings"
	"testing"
)

// TestBasicHexLiteralsUnsigned checks $ literals read as unsigned 16-bit
// values, so $8000-$FFFF are 32768-65535 and work as addresses. They used to
// come out as -32768..-1, which every address argument rejected.
func TestBasicHexLiteralsUnsigned(t *testing.T) {
	c, step := bootClementinaToPrompt(t)
	for _, s := range []string{
		"10 IF $FFFF=65535 THEN POKE 640,1",
		"20 IF $8000=32768 THEN POKE 641,1",
		"30 IF $7FFF=32767 AND $FF=255 AND $0=0 THEN POKE 642,1",
		"40 POKE $9000,77:POKE 643,PEEK($9000)",
		"50 GOTO 50",
	} {
		typeLine(c, step, s)
	}
	typeLine(c, step, "RUN")
	editorTickN(c, step, 500_000)

	require_eq(t, 1, peek(c, 640), "$FFFF is 65535")
	require_eq(t, 1, peek(c, 641), "$8000 is 32768")
	require_eq(t, 1, peek(c, 642), "values below $8000 are unchanged")
	require_eq(t, 77, peek(c, 643), "POKE and PEEK take a hex address above $7FFF")
}

// TestBasicHexLiteralPrint checks PRINT shows hex literals above $7FFF as
// positive numbers.
func TestBasicHexLiteralPrint(t *testing.T) {
	c, step := bootClementinaToPrompt(t)
	typeLine(c, step, "CLS:PRINT $FFFF;$8000;$C001")
	editorTickN(c, step, 200_000)
	if row := strings.TrimRight(printScreenRow(c, 0), " \x00"); row != " 65535  32768  49153" {
		t.Fatalf("PRINT $FFFF;$8000;$C001 gave %q", row)
	}
}

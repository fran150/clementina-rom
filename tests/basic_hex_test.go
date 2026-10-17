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

// TestBasicHexSixDigits checks $ literals take up to 6 hex digits, so every
// MIA RAM address can be written in hex. A 4-digit limit used to keep only the
// last 4 digits, so $14000 read as 16384.
func TestBasicHexSixDigits(t *testing.T) {
	c, step := bootClementinaToPrompt(t)
	typeLine(c, step, "CLS:PRINT $14000;$FFFFFF;$3FFFF;$000001")
	editorTickN(c, step, 200_000)
	if row := strings.TrimRight(printScreenRow(c, 0), " \x00"); row != " 81920  16777215  262143  1" {
		t.Fatalf("PRINT $14000;$FFFFFF;$3FFFF;$000001 gave %q", row)
	}
}

// TestBasicHexSevenDigitsOverflow checks a digit that would take a hex literal
// past $FFFFFF gives OVERFLOW instead of wrapping. Leading zeros don't count.
func TestBasicHexSevenDigitsOverflow(t *testing.T) {
	c, step := bootClementinaToPrompt(t)
	typeLine(c, step, "CLS:PRINT $1000000")
	editorTickN(c, step, 200_000)
	if _, ok := screenContainsRow(c.chips.mia.(videoReader), "?OVERFLOW ERROR"); !ok {
		t.Fatalf("PRINT $1000000 gave %q / %q, want an OVERFLOW error", printScreenRow(c, 0), printScreenRow(c, 1))
	}
	typeLine(c, step, "CLS:PRINT $0000FF")
	editorTickN(c, step, 200_000)
	if row := strings.TrimRight(printScreenRow(c, 0), " \x00"); row != " 255" {
		t.Fatalf("PRINT $0000FF gave %q", row)
	}
}

// TestBasicHexKeepsKeywordLetters checks the tokenizer stores the hex digits
// after a $ as typed. It used to crunch the CD and DEF inside them into
// keywords, so PRINT $CD00 printed 0 and $ACDC printed 10, in a typed line and
// in a stored program alike. A $ that ends a string variable name is not hex.
func TestBasicHexKeepsKeywordLetters(t *testing.T) {
	c, step := bootClementinaToPrompt(t)
	typeLine(c, step, "CLS:PRINT $CD00;$ACDC;$DEF0;$1CD00;$cdef")
	editorTickN(c, step, 200_000)
	if row := strings.TrimRight(printScreenRow(c, 0), " \x00"); row != " 52480  44252  57072  118016  52719" {
		t.Fatalf("PRINT $CD00;$ACDC;$DEF0;$1CD00;$cdef gave %q", row)
	}
	for _, s := range []string{
		`10 A$="HI":B1$="X"+A$:IF LEN(B1$)=3 THEN POKE 640,1`,
		"20 IF $CD00=52480 AND $DEF=3567 THEN POKE 641,1",
		"30 DEF FNA(X)=X*2:IF FNA($CD)=410 THEN POKE 642,1",
		"40 GOTO 40",
	} {
		typeLine(c, step, s)
	}
	typeLine(c, step, "RUN")
	editorTickN(c, step, 500_000)
	require_eq(t, 1, peek(c, 640), "A$ and B1$ are still string variables")
	require_eq(t, 1, peek(c, 641), "hex in a stored program keeps CD and DEF")
	require_eq(t, 1, peek(c, 642), "DEF FN still crunches outside a hex number")
}

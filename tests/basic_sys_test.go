package clementina

import "testing"

// TestBasicSYSReturnsNormally BLOADs (into bank 1, which BASIC never uses) a
// tiny machine-code routine that writes two known bytes and returns (RTS),
// calls it with SYS, and confirms both that it ran and that control
// genuinely came back - the next statement executes, unlike BRUN, which never
// returns. SYS maps the BANK bank for a target at $8000-$BFFF and maps bank 0
// back afterwards.
func TestBasicSYSReturnsNormally(t *testing.T) {
	dir := t.TempDir()
	// LDA #$AA / STA $0280 / LDA $C001 / STA $0281 / RTS, loaded at $8000.
	routine := []byte{0xA9, 0xAA, 0x8D, 0x80, 0x02, 0xAD, 0x01, 0xC0, 0x8D, 0x81, 0x02, 0x60}
	writePRG(t, dir, "R.PRG", 0x8000, routine)

	c, step := bootClementinaToPrompt(t)
	c.SetMiaSDFolder(dir)
	typeLine(c, step, `10 BANK 1:BLOAD "R.PRG"`)
	typeLine(c, step, "30 SYS 32768") // $8000
	typeLine(c, step, "40 POKE 700,42:POKE 701,PEEK(49153) AND 31")
	typeLine(c, step, `50 A$="OK"+"!":POKE 702,LEN(A$)`)
	typeLine(c, step, "60 GOTO 60")
	typeLine(c, step, "RUN")
	editorTickN(c, step, 1_000_000)

	require_eq(t, 0xAA, peek(c, 0x0280), "SYS-called routine ran")
	require_eq(t, 1, peek(c, 0x0281)&0x1F, "it ran with bank 1 mapped")
	require_eq(t, 42, peek(c, 700), "control returned to BASIC after SYS - line 40 ran")
	require_eq(t, 0, peek(c, 701), "bank 0 mapped again after SYS")
	require_eq(t, 3, peek(c, 702), "strings work after SYS")
}

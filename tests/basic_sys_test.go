package clementina

import "testing"

// TestBasicSYSReturnsNormally BLOADs (banked, so no run address is needed -
// an unbanked destination this low would fall inside BASIC's own reclaimable
// region and KERN_LOAD would refuse it without one) a tiny machine-code
// routine that writes two known bytes and returns (RTS), calls it with SYS,
// and confirms both that it ran and that control genuinely came back - the
// next statement executes, unlike BLOAD's own run-address form, which never
// returns.
func TestBasicSYSReturnsNormally(t *testing.T) {
	dir := t.TempDir()
	// LDA #$AA / STA $0200 / LDA #$BB / STA $0201 / RTS, loaded at $8000 bank 1.
	routine := []byte{0xA9, 0xAA, 0x8D, 0x00, 0x02, 0xA9, 0xBB, 0x8D, 0x01, 0x02, 0x60}
	writePRG(t, dir, "R.PRG", 0x8000, 1, routine)

	c, step := bootClementinaToPrompt(t)
	c.SetMiaSDFolder(dir)
	typeLine(c, step, `10 BLOAD "R.PRG"`)
	typeLine(c, step, "20 POKE 49153,1") // select bank 1 before calling into it
	typeLine(c, step, "30 SYS 32768")    // $8000
	typeLine(c, step, "40 POKE 700,42")
	typeLine(c, step, "50 GOTO 50")
	typeLine(c, step, "RUN")
	editorTickN(c, step, 1_000_000)

	require_eq(t, 0xAA, peek(c, 0x0200), "SYS-called routine ran (first POKE)")
	require_eq(t, 0xBB, peek(c, 0x0201), "SYS-called routine ran (second POKE)")
	require_eq(t, 42, peek(c, 700), "control returned to BASIC after SYS - line 40 ran")
}

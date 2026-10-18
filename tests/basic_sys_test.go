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

// The BASIC entry points machine code calls at fixed addresses, after the
// kernel's own jump table (kernel.inc BAS_*).
const (
	basChkcom = 0x0436
	basFrmnum = 0x0439
	basGetadr = 0x043F
	basGetbyt = 0x0442
	basError  = 0x0448
	basLinprt = 0x044B
)

// op assembles one 3-byte instruction with an absolute operand.
func op(opcode byte, addr uint16) []byte { return []byte{opcode, byte(addr), byte(addr >> 8)} }

// sysArgsRoutine reads ",byte,word" after SYS's address the way BASIC's own
// statements do and stores the byte at $0280 and the word at $0281-$0282.
func sysArgsRoutine() []byte {
	var r []byte
	for _, part := range [][]byte{
		op(0x20, basChkcom), op(0x20, basGetbyt), op(0x8E, 0x0280), // JSR, JSR, STX
		op(0x20, basChkcom), op(0x20, basFrmnum), op(0x20, basGetadr), // JSR x3
		op(0x8C, 0x0281), op(0x8D, 0x0282), {0x60}, // STY, STA, RTS
	} {
		r = append(r, part...)
	}
	return r
}

// TestBasicSYSReadsArguments calls a routine with SYS addr,byte,word. It reads
// both arguments through the BAS_* entries, and BASIC goes on with the rest of
// the line.
func TestBasicSYSReadsArguments(t *testing.T) {
	dir := t.TempDir()
	writePRG(t, dir, "A.PRG", 0x8000, sysArgsRoutine())

	c, step := bootClementinaToPrompt(t)
	c.SetMiaSDFolder(dir)
	typeLine(c, step, `10 BANK 1:BLOAD "A.PRG"`)
	typeLine(c, step, "30 SYS 32768,200,4660:POKE 700,42")
	typeLine(c, step, "40 GOTO 40")
	typeLine(c, step, "RUN")
	editorTickN(c, step, 1_000_000)

	require_eq(t, 200, peek(c, 0x0280), "BAS_GETBYT read the byte argument")
	require_eq(t, 0x34, peek(c, 0x0281), "BAS_GETADR returned the word's low byte in Y")
	require_eq(t, 0x12, peek(c, 0x0282), "BAS_GETADR returned the word's high byte in A")
	require_eq(t, 42, peek(c, 700), "BASIC went on after SYS's arguments")
}

// TestBasicSYSErrorMapsBankZero runs the same routine from bank 1 with a byte
// argument of 300, so BAS_GETBYT raises ILLEGAL QUANTITY while bank 1 is
// mapped. The error maps bank 0 back: the string at the top of BASIC's heap
// ($8000-$BFFF) reads correctly afterwards.
func TestBasicSYSErrorMapsBankZero(t *testing.T) {
	dir := t.TempDir()
	writePRG(t, dir, "A.PRG", 0x8000, sysArgsRoutine())

	c, step := bootClementinaToPrompt(t)
	c.SetMiaSDFolder(dir)
	typeLine(c, step, `10 BANK 1:BLOAD "A.PRG"`)
	typeLine(c, step, `20 A$="HEAP"+"!"`)
	typeLine(c, step, "30 SYS 32768,300,1")
	typeLine(c, step, "RUN")
	editorTickN(c, step, 1_000_000)
	fsRowAfter(t, c, "RUN", "?ILLEGAL QUANTITY ERROR IN  30")

	typeLine(c, step, "POKE 700,PEEK(49153) AND 31:POKE 701,ASC(A$)")
	editorTickN(c, step, 200_000)
	require_eq(t, 0, peek(c, 700), "bank 0 mapped after the error")
	require_eq(t, 'H', peek(c, 701), "the heap string reads correctly")
}

// TestBasicSYSPrintsAndRaises calls BAS_LINPRT to print 4660 (with PRINT's
// leading sign space), then raises DIVISION BY ZERO (code 133) through
// BAS_ERROR.
func TestBasicSYSPrintsAndRaises(t *testing.T) {
	dir := t.TempDir()
	var routine []byte
	for _, part := range [][]byte{
		{0xA9, 0x12, 0xA2, 0x34}, op(0x20, basLinprt), // LDA #$12, LDX #$34, JSR
		{0xA2, 133}, op(0x4C, basError), // LDX #133, JMP
	} {
		routine = append(routine, part...)
	}
	writePRG(t, dir, "P.PRG", 0x8000, routine)

	c, step := bootClementinaToPrompt(t)
	c.SetMiaSDFolder(dir)
	typeLine(c, step, `10 BANK 1:BLOAD "P.PRG"`)
	typeLine(c, step, "30 SYS 32768")
	typeLine(c, step, "RUN")
	editorTickN(c, step, 1_000_000)
	fsRowAfter(t, c, "RUN", " 4660")
	fsRowAfter(t, c, " 4660", "?DIVISION BY ZERO ERROR IN  30")
}

// These integration tests run in the emulator's clementina package via a Go
// overlay; tests/run_input.py supplies the freshly built kernel.bin.
package clementina

// Checkpoints use $0280 (640), above both line buffers in the $0200 page
// (BASIC's ends at $0252, WozMon's at $027F), so typed lines never touch them.
// Do not use heap addresses: stored programs can grow through them.

import (
	"fmt"
	"strings"
	"testing"
)

func TestBasicInputPhase(t *testing.T) {
	computer, step := bootClementinaToPrompt(t)
	line := 10
	add := func(s string) {
		for _, part := range strings.Split(s, ":") {
			typeLine(computer, step, fmt.Sprintf("%d %s", line, part))
			line += 10
		}
	}
	// Seed the emulated input block through the real CPU index registers.
	// No user API for writing live input is implied by this test fixture.
	write := func(offset, value int) {
		add("POKE 65505,96")
		add("POKE 65506,2:POKE 65507,1")
		add("POKE 65506,1:POKE 65507,16")
		add(fmt.Sprintf("POKE 65506,0:POKE 65507,%d", offset))
		add(fmt.Sprintf("POKE 65504,%d", value))
	}
	write(9, 128)
	write(32+28, 2)
	write(69, 4)
	write(80, 137)
	write(81, 165)
	write(82, 129)
	write(83, 2)
	write(84, 128)
	write(85, 127)
	write(86, 255)
	write(88, 255)
	add("POKE 640,KEYDOWN(79)")
	add("POKE 641,KEYDOWN(80)")
	add("POKE 642,CONSDOWN(225)")
	add("POKE 643,INPUTDEV(0)")
	add("PADREAD 0")
	add("POKE 644,PADON(0):POKE 645,PADDIR(0)")
	add("POKE 646,PADSTICK(0):POKE 647,PADBTN(0,9)")
	add("POKE 648,PADAXIS(0,0)+128")
	add("POKE 649,PADAXIS(0,1):POKE 650,PADTRIG(0,0)")
	add("A=PADBTN(PADON(1),PADBTN(0,0)*9)")
	add("POKE 651,A")
	// Explicit cached read: changing MIA must not change PADAXIS until PADREAD.
	write(84, 10)
	add("POKE 652,PADAXIS(0,0)+128")
	add("PADREAD 0:POKE 653,PADAXIS(0,0)")
	write(65, 250)
	write(66, 3)
	add("MOUSE DX,DY,B,W,P:POKE 654,DX:POKE 655,DY")
	write(64, 5)
	write(65, 3)
	write(66, 250)
	write(67, 255)
	write(68, 2)
	add("MOUSE DX%,DY%,B%,W%,P%")
	add("POKE 656,DX%:POKE 657,DY%+128:POKE 658,B%")
	add("POKE 659,W%+128:POKE 660,P%")
	add("MOUSE DX,DY,B,W,P:POKE 661,DX:POKE 662,DY")
	add("KEYREPEAT 400,60:KEYRPT 79,0:KEYREPEAT 0")
	add("KEYCLEAR:INPUTMODE 0:POKE 663,123")
	add(fmt.Sprintf("GOTO %d", line))
	typeLine(computer, step, "RUN")
	editorTickN(computer, step, 3_000_000)
	want := []byte{1, 0, 1, 4, 1, 9, 165, 1, 0, 127, 255, 1, 0, 10, 0, 0, 9, 119, 5, 127, 2, 0, 0, 123}
	for i, w := range want {
		if got := peek(computer, uint32(640+i)); got != w {
			t.Errorf("input result %d: want %d got %d", i, w, got)
		}
	}
}

func TestBasicInputRanges(t *testing.T) {
	for _, cmd := range []string{"PRINT KEYDOWN(256)", "PRINT CONSDOWN(-1)", "PRINT INPUTDEV(1)", "PADREAD 4", "PRINT PADAXIS(0,4)", "PRINT PADTRIG(0,2)", "PRINT PADBTN(0,16)", "KEYRPT 79,2", "KEYREPEAT 400,0", "INPUTMODE 3"} {
		t.Run(cmd, func(t *testing.T) {
			c, step := bootClementinaToPrompt(t)
			typeLine(c, step, cmd)
			vr := c.chips.mia.(videoReader)
			b := make([]byte, 1000)
			for i := range b {
				b[i] = vr.DebugReadVideo(uint32(0x10080 + i))
			}
			if !strings.Contains(string(b), "?ILLEGAL QUANTITY") {
				t.Fatalf("expected range error: %s", b)
			}
		})
	}
}

func inputScreen(c *ClementinaComputer) string {
	vr := c.chips.mia.(videoReader)
	b := make([]byte, 1000)
	for i := range b {
		b[i] = vr.DebugReadVideo(uint32(0x10080 + i))
	}
	return string(b)
}

// TestBasicInputLongLine types lines as long as the screen editor's logical
// line (80 characters, two full rows), numbered and direct, and checks BASIC
// keeps every character: the stored line LISTs whole and runs to its last
// statement. The long line goes in between two others, so the program's links
// must survive the insertion. The zero page promised to programs, $98-$DF,
// must stay untouched throughout.
func TestBasicInputLongLine(t *testing.T) {
	c, step := bootClementinaToPrompt(t)
	for a := 0x98; a <= 0xDF; a++ {
		c.chips.baseram.Poke(uint16(a), 0xA5)
	}
	long := `10 A$="` + strings.Repeat("X", 55) + `":POKE 640,LEN(A$)`
	direct := `B$="` + strings.Repeat("Y", 58) + `":POKE 641,LEN(B$)`
	if len(long) != 80 || len(direct) != 80 {
		t.Fatalf("test lines must be 80 characters: %d, %d", len(long), len(direct))
	}
	// The emulated text FIFO holds 64 keys and drops the oldest on overflow,
	// so feed a long line in chunks the editor drains in between.
	typeLong := func(line string) {
		for len(line) > 32 {
			injectKeys(c, []byte(line[:32])...)
			editorTickN(c, step, 300_000)
			line = line[32:]
		}
		typeLine(c, step, line)
	}
	typeLine(c, step, "30 POKE 643,9")
	// The stored line's link is staged at $01FC-$01FD, just below the buffer,
	// and FIX_LINKS stops at a zero link high byte. BASIC sets it as it stores
	// the line; clear it first so stale stack bytes cannot stand in for that.
	c.chips.baseram.Poke(0x01FD, 0)
	typeLong(long)
	typeLine(c, step, "20 POKE 642,7")
	typeLine(c, step, "CLS:LIST")
	screen := inputScreen(c)
	for _, want := range []string{long, "20 POKE 642,7", "30 POKE 643,9"} {
		if !strings.Contains(screen, want) {
			t.Fatalf("LIST lost %q:\n%s", want, screen)
		}
	}
	typeLine(c, step, "RUN")
	editorTickN(c, step, 500_000)
	require_eq(t, 55, peek(c, 640), "80-character program line ran to its last statement")
	require_eq(t, 7, peek(c, 642), "line after the long line ran")
	require_eq(t, 9, peek(c, 643), "last line ran")
	typeLong(direct)
	require_eq(t, 58, peek(c, 641), "80-character direct line ran to its last statement")
	for a := 0x98; a <= 0xDF; a++ {
		require_eq(t, 0xA5, peek(c, uint32(a)), fmt.Sprintf("zero page $%02X written", a))
	}
}

// TestBasicInputAfterWarmStart returns from WozMon to BASIC through
// KERN_WARMSTART, which hands over with S=$FF, then starts the program with
// GOTO, which does not reset the stack the way RUN does. INPUT stores its
// leading comma at $01FF, just below the line buffer; BASIC_WARM_START must
// have lowered the stack, or that store lands on NEWSTT's return address.
func TestBasicInputAfterWarmStart(t *testing.T) {
	c, step := bootClementinaToPrompt(t)
	typeLine(c, step, "10 INPUT A")
	typeLine(c, step, "20 POKE 644,A")
	typeLine(c, step, "30 GOTO 30")
	typeLine(c, step, "MON")
	typeLine(c, step, "Q")
	typeLine(c, step, "GOTO 10")
	typeLine(c, step, "42")
	editorTickN(c, step, 500_000)
	require_eq(t, 42, peek(c, 644), "INPUT after a warm start returned to its program")
}

// TestBasicZeroPageProgramBlock fills the zero page promised to programs,
// $98-$DF, runs a program that uses strings, floats, INPUT, FOR and GOSUB,
// then visits WozMon, stores and examines memory there, and quits back to
// BASIC. The block must come back untouched. The program and its variables
// must survive the trip too: WozMon keeps its variables at $E8-$EF, clear of
// BASIC's $00-$97.
func TestBasicZeroPageProgramBlock(t *testing.T) {
	c, step := bootClementinaToPrompt(t)
	for a := 0x98; a <= 0xDF; a++ {
		c.chips.baseram.Poke(uint16(a), 0xA5)
	}
	typeLine(c, step, `10 A$="X"+STR$(3.25):INPUT B`)
	typeLine(c, step, "20 GOSUB 50:POKE 644,B")
	typeLine(c, step, "30 POKE 645,LEN(A$)")
	typeLine(c, step, "40 END")
	typeLine(c, step, "50 FOR I=1 TO 3:PRINT A$;I*1.5:NEXT:RETURN")
	typeLine(c, step, "RUN")
	typeLine(c, step, "7")
	editorTickN(c, step, 500_000)
	require_eq(t, 7, peek(c, 644), "program ran")
	require_eq(t, 6, peek(c, 645), "string built before INPUT")
	typeLine(c, step, "MON")
	typeLine(c, step, "290: 2A 2B")
	typeLine(c, step, "280.29F")
	typeLine(c, step, "Q")
	require_eq(t, 0x2A, peek(c, 0x290), "WozMon stored the first byte")
	require_eq(t, 0x2B, peek(c, 0x291), "WozMon stored the second byte")
	typeLine(c, step, "POKE 646,B")
	require_eq(t, 7, peek(c, 646), "variable B survived WozMon")
	typeLine(c, step, "CLS:LIST")
	screen := inputScreen(c)
	for _, want := range []string{"20 GOSUB 50:POKE 644,B", "50 FOR I=1 TO 3"} {
		if !strings.Contains(screen, want) {
			t.Fatalf("LIST after WozMon lost %q:\n%s", want, screen)
		}
	}
	typeLine(c, step, "RUN")
	typeLine(c, step, "9")
	editorTickN(c, step, 500_000)
	require_eq(t, 9, peek(c, 644), "program ran again after WozMon")
	for a := 0x98; a <= 0xDF; a++ {
		require_eq(t, 0xA5, peek(c, uint32(a)), fmt.Sprintf("zero page $%02X written", a))
	}
}

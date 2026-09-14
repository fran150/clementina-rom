// These integration tests run in the emulator's clementina package via a Go
// overlay; tests/run_input.py supplies the freshly built kernel.bin.
package clementina

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
	add("POKE 24576,KEYDOWN(79)")
	add("POKE 24577,KEYDOWN(80)")
	add("POKE 24578,CONSDOWN(225)")
	add("POKE 24579,INPUTDEV(0)")
	add("PADREAD 0")
	add("POKE 24580,PADON(0):POKE 24581,PADDIR(0)")
	add("POKE 24582,PADSTICK(0):POKE 24583,PADBTN(0,9)")
	add("POKE 24584,PADAXIS(0,0)+128")
	add("POKE 24585,PADAXIS(0,1):POKE 24586,PADTRIG(0,0)")
	add("A=PADBTN(PADON(1),PADBTN(0,0)*9)")
	add("POKE 24587,A")
	// Explicit cached read: changing MIA must not change PADAXIS until PADREAD.
	write(84, 10)
	add("POKE 24588,PADAXIS(0,0)+128")
	add("PADREAD 0:POKE 24589,PADAXIS(0,0)")
	write(65, 250)
	write(66, 3)
	add("MOUSE DX,DY,B,W,P:POKE 24590,DX:POKE 24591,DY")
	write(64, 5)
	write(65, 3)
	write(66, 250)
	write(67, 255)
	write(68, 2)
	add("MOUSE DX%,DY%,B%,W%,P%")
	add("POKE 24592,DX%:POKE 24593,DY%+128:POKE 24594,B%")
	add("POKE 24595,W%+128:POKE 24596,P%")
	add("MOUSE DX,DY,B,W,P:POKE 24597,DX:POKE 24598,DY")
	add("KEYREPEAT 400,60:KEYRPT 79,0:KEYREPEAT 0")
	add("KEYCLEAR:INPUTMODE 0:POKE 24599,123")
	add(fmt.Sprintf("GOTO %d", line))
	typeLine(computer, step, "RUN")
	editorTickN(computer, step, 3_000_000)
	want := []byte{1, 0, 1, 4, 1, 9, 165, 1, 0, 127, 255, 1, 0, 10, 0, 0, 9, 119, 5, 127, 2, 0, 0, 123}
	for i, w := range want {
		if got := peek(computer, uint32(24576+i)); got != w {
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

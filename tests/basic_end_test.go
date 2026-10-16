package clementina

import "testing"

// TestBasicEndStopsProgram runs END in the middle of a program and checks that
// the line after it never runs. END stops the background sequencer first, and
// that call returns with the Z flag clear; without END saving its flags around
// the call, END returned to the next statement instead of to the prompt.
func TestBasicEndStopsProgram(t *testing.T) {
	c, step := bootClementinaToPrompt(t)
	typeLine(c, step, "10 POKE 640,1:END")
	typeLine(c, step, "20 POKE 641,42")
	typeLine(c, step, "30 GOTO 30")
	typeLine(c, step, "RUN")
	editorTickN(c, step, 500_000)

	require_eq(t, 1, peek(c, 640), "line 10 ran")
	require_eq(t, 0, peek(c, 641), "END stopped the program before line 20")
}

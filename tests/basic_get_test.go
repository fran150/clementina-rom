package clementina

import (
	"strings"
	"testing"
)

// TestBasicGetWaitsWithoutCursor checks that GET waits for a key without
// drawing the cursor (a program's "press a key" screen shows only its own
// text), then returns the key.
func TestBasicGetWaitsWithoutCursor(t *testing.T) {
	c, step := bootClementinaToPrompt(t)
	typeLine(c, step, `10 PRINT "PRESS A KEY";`)
	typeLine(c, step, "20 GET K$:IF K$=\"\" THEN 20")
	typeLine(c, step, "30 POKE 640,ASC(K$)")
	typeLine(c, step, "40 GOTO 40")
	typeLine(c, step, "RUN")
	editorTickN(c, step, 500_000)

	require_eq(t, 0, peek(c, 640), "GET is still waiting")
	require_eq(t, 0, peek(c, 0x0309), "no cursor while GET waits (CURSOR_VISIBLE)")
	require_eq(t, 0, peek(c, 0x037E), "no cursor blink while GET waits (CURSOR_BLINK_ACTIVE)")

	injectKeys(c, 'Z')
	editorTickN(c, step, 500_000)
	require_eq(t, 'Z', peek(c, 640), "GET returned the key")
}

// TestBasicGetCtrlCBreaks checks that Ctrl-C stops a program waiting in GET.
// GET takes the key off the FIFO, so the between-statement Ctrl-C check never
// sees it; a GET loop without an exit used to need a reset.
func TestBasicGetCtrlCBreaks(t *testing.T) {
	c, step := bootClementinaToPrompt(t)
	typeLine(c, step, "10 GET K$:GOTO 10")
	typeLine(c, step, "RUN")
	editorTickN(c, step, 500_000)

	injectKeys(c, 0x03)
	editorTickN(c, step, 500_000)
	if !strings.Contains(timingScreen(c), "BREAK IN  10") {
		t.Fatalf("no BREAK IN  10 on screen after Ctrl-C:\n%q", timingScreen(c))
	}
	typeLine(c, step, "POKE 640,7")
	require_eq(t, 7, peek(c, 640), "back at the prompt")
}

// TestBasicGetCtrlCCont checks that CONT after a Ctrl-C in GET runs the GET
// again, so the program goes on as if the break never happened.
func TestBasicGetCtrlCCont(t *testing.T) {
	c, step := bootClementinaToPrompt(t)
	typeLine(c, step, "10 POKE 640,1:GET K$:POKE 641,ASC(K$)")
	typeLine(c, step, "20 GOTO 20")
	typeLine(c, step, "RUN")
	editorTickN(c, step, 500_000)
	injectKeys(c, 0x03)
	editorTickN(c, step, 500_000)
	typeLine(c, step, "POKE 640,0")
	typeLine(c, step, "CONT")
	editorTickN(c, step, 500_000)
	injectKeys(c, 'Q')
	editorTickN(c, step, 500_000)
	require_eq(t, 0, peek(c, 640), "CONT resumed at the GET, not the start of the line")
	require_eq(t, 'Q', peek(c, 641), "the GET after CONT read the key")
}

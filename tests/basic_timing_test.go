package clementina

// Checkpoints use $0280 (640), above both line buffers in the $0200 page
// (BASIC's ends at $0252, WozMon's at $027F), so typed lines never touch them.
// Do not use heap addresses: stored programs can grow through them.

import (
	"strings"
	"testing"
)

func timingScreen(c *ClementinaComputer) string {
	vr := c.chips.mia.(videoReader)
	b := make([]byte, 1000)
	for i := range b {
		b[i] = vr.DebugReadVideo(uint32(0x10080 + i))
	}
	return string(b)
}
func TestBasicTiming(t *testing.T) {
	c, step := bootClementinaToPrompt(t)
	for _, s := range []string{
		"10 TI=0", "20 A=TICKS(0)", "30 DELAY 80", "40 B=TICKS(0)-A",
		"50 IF B<80 THEN POKE 640,1", "60 IF TI<4 THEN POKE 640,2",
		"70 TI=3600", "80 IF TI<3600 THEN POKE 640,3",
		"90 IF TI>3610 THEN POKE 640,4", "100 DELAY 0",
		"110 POKE 641,123", "120 GOTO 120",
	} {
		typeLine(c, step, s)
	}
	typeLine(c, step, "RUN")
	editorTickN(c, step, 3_000_000)
	require_eq(t, 0, peek(c, 640), "timing bounds")
	require_eq(t, 123, peek(c, 641), "completed delay and TI assignment")
}
func TestBasicTimingBreak(t *testing.T) {
	c, step := bootClementinaToPrompt(t)
	typeLine(c, step, "10 DELAY 60000")
	typeLine(c, step, "20 POKE 640,123")
	typeLine(c, step, "RUN")
	injectKeys(c, 3)
	editorTickN(c, step, 500_000)
	if !strings.Contains(timingScreen(c), "BREAK") {
		t.Fatal("delay ignored Ctrl-C")
	}
	require_eq(t, 0, peek(c, 640), "break must not execute next statement")
}
func TestBasicTimingRanges(t *testing.T) {
	for _, cmd := range []string{"TI=-1", "TI=5184000", "DELAY -1", "DELAY 65536", "PRINT TICKS(1)", "FOR TI=1 TO 2"} {
		t.Run(cmd, func(t *testing.T) {
			c, step := bootClementinaToPrompt(t)
			typeLine(c, step, cmd)
			if !strings.Contains(timingScreen(c), "?ILLEGAL QUANTITY") {
				t.Fatalf("no range error: %s", timingScreen(c))
			}
		})
	}
}

func TestBasicTimingBackgroundMusic(t *testing.T) {
	c, step := bootClementinaToPrompt(t)
	typeLine(c, step, "SNDON:WAVE 0,1:ADSR 0,0,4,10,4")
	// PLAY is retired: background music is a TRACK on MIA's sequencer. The
	// emulator only renders audio - and so only advances the sequencer - when
	// a test drives it, so render samples explicitly (see track_band_test.go).
	typeLine(c, step, `10 TRACK 0,"T120 L4 C D E F":BAND 0,1`)
	typeLine(c, step, "20 DELAY 60000")
	injectKeys(c, []byte("RUN")...)
	injectKeys(c, keyCR)
	editorTickN(c, step, 300_000)
	audio := c.chips.mia.(audioAdvancer)
	audio.DebugSetAudioActive(true)
	// A T120 quarter note is 24000*60/120 = 12000 sequencer ticks. MIA
	// renders 48 kHz frames on a 24 kHz sequencer tick, so a tick is two frames.
	const framesPerTick = 2
	audio.DebugAudioReadPCM(2000 * framesPerTick) // tick 2000: inside the first note
	first, _, _, _ := audio.DebugAudioVoiceState(0)
	editorTickN(c, step, 600_000)
	audio.DebugAudioReadPCM(12000 * framesPerTick) // cumulative tick 14000: inside the second note
	second, _, _, _ := audio.DebugAudioVoiceState(0)
	if first == second {
		t.Fatal("music stopped advancing during delay")
	}
	injectKeys(c, 3)
	editorTickN(c, step, 500_000)
	if !strings.Contains(timingScreen(c), "BREAK") {
		t.Fatal("delay with music ignored break")
	}
}
func TestBasicTimingVariableCompatibility(t *testing.T) {
	c, step := bootClementinaToPrompt(t)
	for _, s := range []string{
		"10 TI=60", "20 TIME=120", "30 A=TI", "40 IF A<120 THEN POKE 640,1",
		"50 TI%=7", "60 DIM TI(2)", "70 TI(1)=9", "80 B=TI(1)+TI%",
		"90 IF B<>16 THEN POKE 640,2", `100 TI$="ABC"`, `110 IF TI$<>"ABC" THEN POKE 640,3`,
		"120 IF TI<120 THEN POKE 640,4", "130 TI=0", "140 POKE 641,123", "150 GOTO 150",
	} {
		typeLine(c, step, s)
	}
	typeLine(c, step, "RUN")
	editorTickN(c, step, 500_000)
	require_eq(t, 0, peek(c, 640), "TI scalar/typed variable/array coexistence")
	require_eq(t, 123, peek(c, 641), "TI variable test completed")
}

package clementina

import "testing"

// TestBasicTrackNumberRange checks TRACK's music numbers are range-checked
// before they wrap: they used to be read modulo 256, so T300 played as T44,
// O256 as O0 and L260 as L4. T0 is outside T's 1-255 too, and lengths are
// 1-64.
func TestBasicTrackNumberRange(t *testing.T) {
	for _, tc := range []struct {
		music string
		ok    bool
	}{
		{"T255 O7 W4 V15 L64 C64", true},
		{"T1 L1 C1...", true},
		{"T300 C", false},
		{"T256 C", false},
		{"T0 C", false},
		{"O256 C", false},
		{"W260 C", false},
		{"V16 C", false},
		{"L260 C", false},
		{"L65 C", false},
		{"L0 C", false},
		{"C65", false},
		{"C264", false},
		{"R0", false},
		{"R260", false},
	} {
		t.Run(tc.music, func(t *testing.T) {
			c, step := bootClementinaToPrompt(t)
			vr := c.chips.mia.(videoReader)
			typeLine(c, step, "CLS")
			typeLine(c, step, `TRACK 0,"`+tc.music+`"`)
			_, bad := screenContainsRow(vr, "?ILLEGAL QUANTITY")
			if bad == tc.ok {
				dumpScreen(t, vr)
				t.Fatalf("%q: want ok=%v", tc.music, tc.ok)
			}
		})
	}
}

// TestBasicTrackMML checks TRACK's MML timing and volume: T is quarter notes a
// minute (120 by default), lengths are 1-64 with any number of dots, and V n
// emits SET_VOL n*17. At T130 a quarter note is 11076.92 sequencer ticks: the
// remainder carries into the next note, so three quarters end at tick 33230,
// floor(3*1440000/130), instead of drifting.
func TestBasicTrackMML(t *testing.T) {
	c, step := bootClementinaToPrompt(t)
	typeLine(c, step, `10 TRACK 0,"C"`)
	typeLine(c, step, `20 TRACK 1,"C64 C3 C4.. L12 C R8."`)
	typeLine(c, step, `30 TRACK 2,"T130 C C C"`)
	typeLine(c, step, `40 TRACK 3,"V15 V0 V8 C"`)
	typeLine(c, step, "50 GOTO 50")
	typeLine(c, step, "RUN")
	editorTickN(c, step, 3_000_000)

	dur := func(voice, offset uint32) int {
		return int(peekSeq(c, voice, offset)) | int(peekSeq(c, voice, offset+1))<<8 | int(peekSeq(c, voice, offset+2))<<16
	}
	for _, tc := range []struct {
		voice, offset uint32
		want          int
		what          string
	}{
		{0, 3, 12000, "a quarter note at the default T120"},
		{1, 3, 750, "C64"},
		{1, 9, 16000, "C3, a third of a whole note"},
		{1, 15, 21000, "C4.., a quarter and two dots"},
		{1, 21, 4000, "L12 C"},
		{1, 25, 9000, "R8., a dotted eighth rest"},
		{2, 3, 11076, "the first T130 quarter"},
		{2, 9, 11077, "the second, with the first's remainder"},
		{2, 15, 11077, "the third, ending at tick 33230"},
	} {
		if got := dur(tc.voice, tc.offset); got != tc.want {
			t.Errorf("%s: want %d ticks, got %d", tc.what, tc.want, got)
		}
	}
	require_eq(t, 0x02, peekSeq(c, 1, 24), "REST after the notes")
	for i, want := range []int{0x06, 255, 0x06, 0, 0x06, 136, 0x01} {
		require_eq(t, want, peekSeq(c, 3, uint32(i)), "V15 V0 V8 as SET_VOL 255, 0 and 136, then the note")
	}
}

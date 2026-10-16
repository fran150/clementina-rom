package clementina

import "testing"

// TestBasicTrackNumberRange checks TRACK's music numbers are range-checked
// before they wrap: they used to be read modulo 256, so T300 played as T44,
// O256 as O0 and L260 as L4. T0 is outside T's 1-255 too.
func TestBasicTrackNumberRange(t *testing.T) {
	for _, tc := range []struct {
		music string
		ok    bool
	}{
		{"T255 O7 W4 L32 C32", true},
		{"T300 C", false},
		{"T256 C", false},
		{"T0 C", false},
		{"O256 C", false},
		{"W260 C", false},
		{"L260 C", false},
		{"C264", false},
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

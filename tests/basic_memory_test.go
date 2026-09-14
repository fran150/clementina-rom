package clementina

import (
	"fmt"
	"strings"
	"testing"
)

func TestBasicMemoryBytesAndNestedArguments(t *testing.T) {
	c, step := bootClementinaToPrompt(t)
	lines := []string{
		"10 MPOKE 200000,123", "20 MPOKE 262143,255", "30 POKE 24576,MPEEK(200000)",
		"40 POKE 24577,MPEEK(262143)", "50 MPOKE 200001,MPEEK(200000)",
		"60 MPOKE 200002,3", "70 MPOKE 200003,2", "80 MCOPY 200000,200010,MPEEK(200002)",
		"90 MFILL 200020,MPEEK(200003),MPEEK(200000)",
		"100 POKE 24578,MPEEK(200001)", "110 POKE 24579,MPEEK(200012)",
		"120 POKE 24580,MPEEK(200021)", "130 MPOKE 200030,123.9",
		"140 POKE 24581,MPEEK(200030.9)", "150 POKE 24582,42", "160 GOTO 160",
	}
	// Keep each edited line within one screen row; split the long fill statement.
	lines[8] = "90 N=MPEEK(200003):V=MPEEK(200000)"
	lines = append(lines[:9], append([]string{"95 MFILL 200020,N,V"}, lines[9:]...)...)
	for _, line := range lines {
		typeLine(c, step, line)
	}
	typeLine(c, step, "RUN")
	editorTickN(c, step, 1_000_000)
	want := []byte{123, 255, 123, 3, 123, 123, 42}
	for i, w := range want {
		require_eq(t, int(w), peek(c, uint32(24576+i)), fmt.Sprintf("memory result %d", i))
	}
}

func TestBasicMemoryOverlap(t *testing.T) {
	for _, tc := range []struct{ src, dst, n int }{{0, 1, 32}, {1, 0, 32}, {0, 7, 40}, {7, 0, 40}, {0, 0, 48}, {0, 80, 48}, {80, 0, 48}} {
		t.Run(fmt.Sprint(tc), func(t *testing.T) {
			c, step := bootClementinaToPrompt(t)
			vr := c.chips.mia.(videoReader)
			typeLine(c, step, "10 FOR I=0 TO 127")
			typeLine(c, step, "20 MPOKE 200240+I,I:NEXT I")
			typeLine(c, step, fmt.Sprintf("30 MCOPY %d,%d,%d", 200240+tc.src, 200240+tc.dst, tc.n))
			typeLine(c, step, "40 POKE 24576,42")
			typeLine(c, step, "50 GOTO 50")
			typeLine(c, step, "RUN")
			editorTickN(c, step, 2_000_000)
			require_eq(t, 42, peek(c, 24576), "copy completed")
			want := make([]byte, 128)
			for i := range want {
				want[i] = byte(i)
			}
			copy(want[tc.dst:tc.dst+tc.n], want[tc.src:tc.src+tc.n])
			for i, w := range want {
				require_eq(t, int(w), vr.DebugReadVideo(uint32(200240+i)), fmt.Sprintf("overlap byte %d", i))
			}
		})
	}
}

func TestBasicMemoryLargeAndBoundary(t *testing.T) {
	c, step := bootClementinaToPrompt(t)
	vr := c.chips.mia.(videoReader)
	for _, line := range []string{
		"10 MFILL 131072,65536,37", "12 MPOKE 131072,201", "14 MPOKE 196607,204",
		"20 MCOPY 131072,196608,65536", "25 POKE 24577,MPEEK(262143)",
		"30 MPOKE 262143,99", "40 MFILL 262143,0,2", "50 MCOPY 131072,262143,0",
		"60 MCOPY 0,0,262144", "70 POKE 24576,42", "80 GOTO 80",
	} {
		typeLine(c, step, line)
	}
	typeLine(c, step, "RUN")
	editorTickN(c, step, 1_000_000)
	require_eq(t, 42, peek(c, 24576), "large copy completed")
	for _, a := range []uint32{131073, 163839, 163840, 196606, 229376, 262142} {
		require_eq(t, 37, vr.DebugReadVideo(a), fmt.Sprintf("large block byte %d", a))
	}
	require_eq(t, 201, vr.DebugReadVideo(131072), "source head")
	require_eq(t, 201, vr.DebugReadVideo(196608), "copied head")
	require_eq(t, 204, vr.DebugReadVideo(196607), "source tail")
	require_eq(t, 204, peek(c, 24577), "copied tail across 65535-byte chunk boundary")
	require_eq(t, 99, vr.DebugReadVideo(262143), "last RAM byte / empty operations")
}

func TestBasicMemoryFullFill(t *testing.T) {
	c, step := bootClementinaToPrompt(t)
	vr := c.chips.mia.(videoReader)
	for _, line := range []string{"10 MFILL 0,262144,0", "20 POKE 24576,42", "30 GOTO 30"} {
		typeLine(c, step, line)
	}
	typeLine(c, step, "RUN")
	editorTickN(c, step, 1_000_000)
	require_eq(t, 42, peek(c, 24576), "full 256 KiB fill completed")
	for _, a := range []uint32{0, 65535, 65536, 131071, 131072, 196607, 196608, 262143} {
		require_eq(t, 0, vr.DebugReadVideo(a), fmt.Sprintf("full fill byte %d", a))
	}
}

func TestBasicMemoryRanges(t *testing.T) {
	for _, cmd := range []string{"MPOKE 262144,7", "MPOKE -1,7", "MPOKE 200000,256", "PRINT MPEEK(262144)", "PRINT MPEEK(-1)", "MFILL 262143,2,7", "MCOPY 262143,200000,2", "MCOPY 200000,262143,2", "MFILL 200000,-1,7", "MFILL 0,262145,7"} {
		t.Run(cmd, func(t *testing.T) {
			c, step := bootClementinaToPrompt(t)
			vr := c.chips.mia.(videoReader)
			typeLine(c, step, "MPOKE 200000,99")
			typeLine(c, step, "MPOKE 262143,88")
			typeLine(c, step, cmd)
			b := make([]byte, 1000)
			for i := range b {
				b[i] = vr.DebugReadVideo(uint32(0x10080 + i))
			}
			if !strings.Contains(string(b), "?ILLEGAL QUANTITY") {
				t.Fatalf("expected range error for %s", cmd)
			}
			require_eq(t, 99, vr.DebugReadVideo(200000), "invalid command changed memory")
			require_eq(t, 88, vr.DebugReadVideo(262143), "overflow wrote partial block")
		})
	}
}

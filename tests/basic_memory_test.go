package clementina

// Checkpoints use $0200 (512), the WozMon buffer, which is idle during BASIC.
// Do not use heap addresses: stored programs can grow through them.

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// Verify that 32-bit file operations leave the stored program unchanged.
func TestProgramTextIntegrityDuringSeek32(t *testing.T) {
	dir := t.TempDir()
	f, err := os.Create(filepath.Join(dir, "BIG"))
	if err != nil {
		t.Fatal(err)
	}
	if err = f.Truncate(4294967295); err != nil {
		f.Close()
		t.Fatal(err)
	}
	f.Close()
	c, step := bootClementinaToPrompt(t)
	c.SetMiaSDFolder(dir)
	for _, l := range []string{
		`10 OPEN "BIG" FOR INPUT AS #1`,
		`20 N=4294967295`,
		`30 IF FSIZE(1)=N THEN POKE 512,1`,
		`40 SEEK#1,2147483648`,
		`50 P=FPOS(1)`,
		`60 IF P=2147483648 THEN POKE 513,1`,
		`70 SEEK#1,N`,
		`80 IF FPOS(1)=N THEN POKE 514,1`,
		`90 SEEK#1,16777217.9`,
		`100 P=FPOS(1)`,
		`110 IF P=16777217 THEN POKE 515,1`,
		`120 CLOSE #1`,
		`130 POKE 516,42`,
		`140 GOTO 140`,
	} {
		typeLine(c, step, l)
	}

	// Read the program bounds through symbols from this build, so the check
	// follows both ROM growth and zero-page layout changes.
	word := func(addr uint32) uint32 {
		return uint32(peek(c, addr)) | uint32(peek(c, addr+1))<<8
	}
	start, end := word(basicTextPointer), word(basicVariablesPointer)
	if start >= end || end > 0xC000 {
		t.Fatalf("invalid program bounds: $%04X-$%04X", start, end)
	}
	before := make([]byte, end-start)
	for i := range before {
		before[i] = peek(c, start+uint32(i))
	}
	typeLine(c, step, "RUN")
	editorTickN(c, step, 2_000_000)
	for i, want := range before {
		if got := peek(c, start+uint32(i)); got != want {
			t.Errorf("program byte $%04X changed: want %02X got %02X", start+uint32(i), want, got)
		}
	}
	for i, want := range []int{1, 1, 1, 1, 42} {
		require_eq(t, want, peek(c, uint32(512+i)), fmt.Sprintf("seek checkpoint %d", i))
	}
}

func TestBasicMemoryBytesAndNestedArguments(t *testing.T) {
	c, step := bootClementinaToPrompt(t)
	lines := []string{
		"10 MPOKE 200000,123", "20 MPOKE 262143,255", "30 POKE 512,MPEEK(200000)",
		"40 POKE 513,MPEEK(262143)", "50 MPOKE 200001,MPEEK(200000)",
		"60 MPOKE 200002,3", "70 MPOKE 200003,2", "80 MCOPY 200000,200010,MPEEK(200002)",
		"90 MFILL 200020,MPEEK(200003),MPEEK(200000)",
		"100 POKE 514,MPEEK(200001)", "110 POKE 515,MPEEK(200012)",
		"120 POKE 516,MPEEK(200021)", "130 MPOKE 200030,123.9",
		"140 POKE 517,MPEEK(200030.9)", "150 POKE 518,42", "160 GOTO 160",
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
		require_eq(t, int(w), peek(c, uint32(512+i)), fmt.Sprintf("memory result %d", i))
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
			typeLine(c, step, "40 POKE 512,42")
			typeLine(c, step, "50 GOTO 50")
			typeLine(c, step, "RUN")
			editorTickN(c, step, 2_000_000)
			require_eq(t, 42, peek(c, 512), "copy completed")
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

func TestBasicHexLiterals(t *testing.T) {
	c, step := bootClementinaToPrompt(t)
	lines := []string{
		"10 POKE 512,$FF",
		"20 POKE 513,$00",
		"30 POKE 514,$0A+$05",
		"40 A=$10:POKE 515,A*2",
		"50 POKE 516,42",
		"60 GOTO 60",
	}
	for _, line := range lines {
		typeLine(c, step, line)
	}
	typeLine(c, step, "RUN")
	editorTickN(c, step, 1_000_000)
	want := []byte{255, 0, 15, 32, 42}
	for i, w := range want {
		require_eq(t, int(w), peek(c, uint32(512+i)), "hex literal result")
	}
}

func TestBasicMemoryLargeAndBoundary(t *testing.T) {
	c, step := bootClementinaToPrompt(t)
	vr := c.chips.mia.(videoReader)
	for _, line := range []string{
		"10 MFILL 131072,65536,37", "12 MPOKE 131072,201", "14 MPOKE 196607,204",
		"20 MCOPY 131072,196608,65536", "25 POKE 513,MPEEK(262143)",
		"30 MPOKE 262143,99", "40 MFILL 262143,0,2", "50 MCOPY 131072,262143,0",
		"60 MCOPY 0,0,262144", "70 POKE 512,42", "80 GOTO 80",
	} {
		typeLine(c, step, line)
	}
	typeLine(c, step, "RUN")
	editorTickN(c, step, 1_000_000)
	require_eq(t, 42, peek(c, 512), "large copy completed")
	for _, a := range []uint32{131073, 163839, 163840, 196606, 229376, 262142} {
		require_eq(t, 37, vr.DebugReadVideo(a), fmt.Sprintf("large block byte %d", a))
	}
	require_eq(t, 201, vr.DebugReadVideo(131072), "source head")
	require_eq(t, 201, vr.DebugReadVideo(196608), "copied head")
	require_eq(t, 204, vr.DebugReadVideo(196607), "source tail")
	require_eq(t, 204, peek(c, 513), "copied tail across 65535-byte chunk boundary")
	require_eq(t, 99, vr.DebugReadVideo(262143), "last RAM byte / empty operations")
}

func TestBasicMemoryFullFill(t *testing.T) {
	c, step := bootClementinaToPrompt(t)
	vr := c.chips.mia.(videoReader)
	for _, line := range []string{"10 MFILL 0,262144,0", "20 POKE 512,42", "30 GOTO 30"} {
		typeLine(c, step, line)
	}
	typeLine(c, step, "RUN")
	editorTickN(c, step, 1_000_000)
	require_eq(t, 42, peek(c, 512), "full 256 KiB fill completed")
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

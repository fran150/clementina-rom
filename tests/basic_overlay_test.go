package clementina

import (
	"strings"
	"testing"
)

func TestBasicOverlayControls(t *testing.T) {
	c, step := bootClementinaToPrompt(t)
	vr := c.chips.mia.(videoReader)
	typeLine(c, step, "BGON:SPRON:OVLOFF")
	require_eq(t, 5, vr.DebugReadVideo(0x21), "hide only overlay")
	typeLine(c, step, "PRINT \"HIDDEN OVERLAY TEXT\"")
	b := make([]byte, 1000)
	for i := range b {
		b[i] = vr.DebugReadVideo(uint32(0x10080 + i))
	}
	if !strings.Contains(string(b), "HIDDEN OVERLAY TEXT") {
		t.Fatal("hidden console did not retain output")
	}
	require_eq(t, 5, vr.DebugReadVideo(0x21), "READY keeps overlay hidden")
	typeLine(c, step, "OVLON:OVLON")
	require_eq(t, 7, vr.DebugReadVideo(0x21), "show preserves other layers")
	typeLine(c, step, "OVLBANK 7:OVLALT 6")
	require_eq(t, 7, vr.DebugReadVideo(0x2a), "primary bank")
	require_eq(t, 6, vr.DebugReadVideo(0x2b), "alternate bank")
	require_eq(t, 0, vr.DebugReadVideo(0x28), "background bank unchanged")
	require_eq(t, 0, vr.DebugReadVideo(0x2c), "sprite bank unchanged")
	require_eq(t, 3, vr.DebugReadVideo(0x2d), "bank modes unchanged")
	require_eq(t, 0, vr.DebugReadVideo(0x2e), "planes unchanged")
	typeLine(c, step, "OVLBANK 0:OVLALT 1")
	require_eq(t, 0, vr.DebugReadVideo(0x2a), "restore primary")
	require_eq(t, 1, vr.DebugReadVideo(0x2b), "restore alternate")
}

func TestBasicOverlayProgramAndListing(t *testing.T) {
	c, step := bootClementinaToPrompt(t)
	vr := c.chips.mia.(videoReader)
	for _, line := range []string{"10 OVLOFF", "20 OVLBANK 4", "30 OVLALT 5", "40 OVLON", "50 GOTO 50"} {
		typeLine(c, step, line)
	}
	typeLine(c, step, "LIST")
	b := make([]byte, 1000)
	for i := range b {
		b[i] = vr.DebugReadVideo(uint32(0x10080 + i))
	}
	for _, word := range []string{"OVLOFF", "OVLBANK", "OVLALT", "OVLON"} {
		if !strings.Contains(string(b), word) {
			t.Fatalf("LIST lost %s", word)
		}
	}
	typeLine(c, step, "RUN")
	editorTickN(c, step, 1_000_000)
	require_eq(t, 2, vr.DebugReadVideo(0x21), "stored overlay enable")
	require_eq(t, 4, vr.DebugReadVideo(0x2a), "stored primary bank")
	require_eq(t, 5, vr.DebugReadVideo(0x2b), "stored alternate bank")
}

func TestBasicOverlayInvalidBanks(t *testing.T) {
	for _, cmd := range []string{"OVLBANK 8", "OVLALT 8", "OVLBANK -1", "OVLALT 256"} {
		t.Run(cmd, func(t *testing.T) {
			c, step := bootClementinaToPrompt(t)
			vr := c.chips.mia.(videoReader)
			typeLine(c, step, cmd)
			b := make([]byte, 1000)
			for i := range b {
				b[i] = vr.DebugReadVideo(uint32(0x10080 + i))
			}
			if !strings.Contains(string(b), "?ILLEGAL QUANTITY") {
				t.Fatal("missing range error")
			}
			require_eq(t, 0, vr.DebugReadVideo(0x2a), "invalid bank preserves primary")
			require_eq(t, 1, vr.DebugReadVideo(0x2b), "invalid bank preserves alternate")
		})
	}
}

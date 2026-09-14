package mia

import (
	"github.com/stretchr/testify/require"
	"os"
	"path/filepath"
	"testing"
)

func TestEmulatedMiaFSFileInfo(t *testing.T) {
	dir := t.TempDir()
	require.NoError(t, os.WriteFile(filepath.Join(dir, "A"), []byte("abcd"), 0600))
	require.NoError(t, os.WriteFile(filepath.Join(dir, "B"), []byte("xy"), 0600))
	circuit := newSDTestCircuit(t, dir)
	c := circuit.chip
	for slot, name := range []string{"A", "B"} {
		c.memory[miaSDControlOffset+miaSDControlHandleSelect] = byte(slot)
		sdWritePath(c, name)
		c.memory[miaSDControlOffset+miaSDControlOpenMode] = 0
		circuit.write(miaRegCmdTrigger, miaCmdFSOpen)
		require.Zero(t, sdControlByte(c, miaSDControlLastError))
		c.sdWriteU32(miaSDControlOffset+miaSDControlFilePos0, uint32(slot+1))
		circuit.write(miaRegCmdTrigger, miaCmdFSSeek)
	}
	for _, slot := range []byte{0, 1, 0} {
		c.memory[miaSDControlOffset+miaSDControlHandleSelect] = slot
		// Query must replace stale shared fields without seeking to their value.
		c.sdWriteU32(miaSDControlOffset+miaSDControlFilePos0, 999)
		circuit.write(miaRegCmdTrigger, miaCmdFSFileInfo)
		require.Zero(t, sdControlByte(c, miaSDControlLastError))
		require.Equal(t, uint32(slot+1), c.sdReadU32(miaSDControlOffset+miaSDControlFilePos0))
		require.Equal(t, []uint32{4, 2}[slot], c.sdReadU32(miaSDControlOffset+miaSDControlFileSize0))
	}
	for _, tc := range []struct{ slot, err byte }{{2, miaErrorFSNoFileOpen}, {16, miaErrorFSInvalidHandle}} {
		c.memory[miaSDControlOffset+miaSDControlHandleSelect] = tc.slot
		circuit.write(miaRegCmdTrigger, miaCmdFSFileInfo)
		require.Equal(t, tc.err, sdControlByte(c, miaSDControlLastError))
	}
	for _, slot := range []byte{0, 1} {
		c.memory[miaSDControlOffset+miaSDControlHandleSelect] = slot
		circuit.write(miaRegCmdTrigger, miaCmdFSClose)
	}
}

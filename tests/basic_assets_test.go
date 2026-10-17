package clementina

import (
	"fmt"
	"os"
	"path/filepath"
	"testing"
)

// The video asset commands take the path first, then where, then (saves
// only) how many. Loads take the whole file; a left-out cell, offset or index
// is 0, and a save's left-out count is the rest of the table, bank or sprite
// list. See docs/basic-video.md.

func writeAsset(t *testing.T, dir, name string, data []byte) {
	t.Helper()
	if err := os.WriteFile(filepath.Join(dir, name), data, 0o644); err != nil {
		t.Fatal(err)
	}
}

func readAsset(t *testing.T, dir, name string, size int) []byte {
	t.Helper()
	data, err := os.ReadFile(filepath.Join(dir, name))
	if err != nil {
		t.Fatal(err)
	}
	if len(data) != size {
		t.Fatalf("%s is %d bytes, want %d", name, len(data), size)
	}
	return data
}

// TestBasicAssetLoadsPathFirst loads each asset kind with and without its
// optional cell, offset or index.
func TestBasicAssetLoadsPathFirst(t *testing.T) {
	dir := t.TempDir()
	writeAsset(t, dir, "T.BIN", []byte{11, 22, 33})
	writeAsset(t, dir, "P.PAL", []byte{0xA1, 0xA2})
	oam := []byte{1, 2, 3, 4, 5, 6, 7, 8, 9, 10}
	writeAsset(t, dir, "S.OAM", oam)

	c, step := bootClementinaToPrompt(t)
	c.SetMiaSDFolder(dir)
	for _, l := range []string{
		`10 NTLOAD "T.BIN",2,10:NTLOAD "T.BIN",3`,
		`20 ATRLOAD "T.BIN",1,5:ATRLOAD "T.BIN",4`,
		`30 CHRLOAD "T.BIN",1,100:CHRLOAD "T.BIN",2`,
		`40 PALLOAD "P.PAL",3,2:PALLOAD "P.PAL",4`,
		`50 OAMLOAD "S.OAM",7:OAMLOAD "S.OAM"`,
		"60 POKE 640,42",
		"70 GOTO 70",
	} {
		typeLine(c, step, l)
	}
	typeLine(c, step, "RUN")
	editorTickN(c, step, 3_000_000)

	require_eq(t, 42, peek(c, 640), "every load ran")
	for i, want := range []int{11, 22, 33} {
		require_eq(t, want, peekBGNT(c, 2, 10+i), fmt.Sprintf("NT table 2 cell %d", 10+i))
		require_eq(t, want, peekBGNT(c, 3, i), fmt.Sprintf("NT table 3 cell %d", i))
		require_eq(t, want, peekBGAttr(c, 1, 5+i), fmt.Sprintf("ATR table 1 cell %d", 5+i))
		require_eq(t, want, peekBGAttr(c, 4, i), fmt.Sprintf("ATR table 4 cell %d", i))
		require_eq(t, want, peekCHR(c, 1, 100+i), fmt.Sprintf("CHR bank 1 byte %d", 100+i))
		require_eq(t, want, peekCHR(c, 2, i), fmt.Sprintf("CHR bank 2 byte %d", i))
	}
	require_eq(t, 0xA1, peekPalette(c, 3, 2), "palette bank 3 byte 2")
	require_eq(t, 0xA2, peekPalette(c, 3, 3), "palette bank 3 byte 3")
	require_eq(t, 0xA1, peekPalette(c, 4, 0), "palette bank 4 byte 0")
	for n := 0; n < 2; n++ {
		for f := 0; f < 5; f++ {
			want := int(oam[n*5+f])
			require_eq(t, want, peekOAM(c, n, f), fmt.Sprintf("sprite %d field %d", n, f))
			require_eq(t, want, peekOAM(c, 7+n, f), fmt.Sprintf("sprite %d field %d", 7+n, f))
		}
	}
}

// TestBasicAssetSavesDefaultCount saves each asset kind with a count and
// with the count left out (the rest of the table, bank or sprite list).
func TestBasicAssetSavesDefaultCount(t *testing.T) {
	dir := t.TempDir()
	c, step := bootClementinaToPrompt(t)
	c.SetMiaSDFolder(dir)
	for _, l := range []string{
		"10 DATA 44,55,66",
		"20 NTREAD 2,990,3:RESTORE:ATRREAD 1,0,3",
		"25 RESTORE:CHRREAD 1,6140,3",
		`30 NTSAVE "N3.BIN",2,990,3`,
		`32 NTSAVE "NR.BIN",2,990:NTSAVE "NA.BIN",5`,
		`40 ATRSAVE "AR.BIN",1:ATRSAVE "A2.BIN",1,0,2`,
		`50 CHRSAVE "CR.BIN",1,6140`,
		`52 CHRSAVE "C2.BIN",1,6141,2:CHRSAVE "CA.BIN",3`,
		`60 PALSAVE "PR.BIN",3,2:PALSAVE "P2.BIN",3,2,2`,
		`62 PALSAVE "PA.BIN",5`,
		`70 OAMSAVE "OR.OAM",254:OAMSAVE "O1.OAM",2,1`,
		`72 OAMSAVE "OA.OAM"`,
		"80 POKE 640,42",
		"90 GOTO 90",
	} {
		typeLine(c, step, l)
	}
	typeLine(c, step, "RUN")
	editorTickN(c, step, 4_000_000)

	require_eq(t, 42, peek(c, 640), "every save ran")
	if got := readAsset(t, dir, "N3.BIN", 3); string(got) != string([]byte{44, 55, 66}) {
		t.Fatalf("N3.BIN = %v", got)
	}
	if got := readAsset(t, dir, "NR.BIN", 10); got[0] != 44 || got[2] != 66 {
		t.Fatalf("NR.BIN = %v", got)
	}
	readAsset(t, dir, "NA.BIN", 1000)
	if got := readAsset(t, dir, "AR.BIN", 1000); got[1] != 55 {
		t.Fatalf("AR.BIN starts %v", got[:3])
	}
	if got := readAsset(t, dir, "A2.BIN", 2); string(got) != string([]byte{44, 55}) {
		t.Fatalf("A2.BIN = %v", got)
	}
	if got := readAsset(t, dir, "CR.BIN", 4); string(got[:3]) != string([]byte{44, 55, 66}) {
		t.Fatalf("CR.BIN = %v", got)
	}
	if got := readAsset(t, dir, "C2.BIN", 2); string(got) != string([]byte{55, 66}) {
		t.Fatalf("C2.BIN = %v", got)
	}
	readAsset(t, dir, "CA.BIN", 6144)
	readAsset(t, dir, "PR.BIN", 14)
	readAsset(t, dir, "P2.BIN", 2)
	readAsset(t, dir, "PA.BIN", 16)
	readAsset(t, dir, "OR.OAM", 10)
	readAsset(t, dir, "O1.OAM", 5)
	readAsset(t, dir, "OA.OAM", 1280)
}

// TestBasicAssetArgumentErrors checks the old path-last form, an extra
// argument and an out-of-range offset all fail before anything is written.
func TestBasicAssetArgumentErrors(t *testing.T) {
	for _, tc := range []struct{ line, err string }{
		{`CHRLOAD 1,100,3,"T.BIN"`, "?TYPE MISMATCH"},
		{`NTLOAD "T.BIN",2,10,3`, "?SYNTAX ERROR"},
		{`OAMLOAD "T.BIN",0,2`, "?SYNTAX ERROR"},
		{`PALLOAD "T.BIN",3,16`, "?ILLEGAL QUANTITY"},
		{`CHRLOAD "T.BIN",8`, "?ILLEGAL QUANTITY"},
		{`ATRLOAD "T.BIN",0,1000`, "?ILLEGAL QUANTITY"},
		{`NTSAVE "X.BIN",0,0,1,2`, "?SYNTAX ERROR"},
	} {
		t.Run(tc.line, func(t *testing.T) {
			dir := t.TempDir()
			writeAsset(t, dir, "T.BIN", []byte{11, 22, 33})
			c, step := bootClementinaToPrompt(t)
			c.SetMiaSDFolder(dir)
			typeLine(c, step, "CLS:"+tc.line)
			editorTickN(c, step, 500_000)
			vr := c.chips.mia.(videoReader)
			if _, ok := screenContainsRow(vr, tc.err); !ok {
				dumpScreen(t, vr)
				t.Fatalf("missing %s", tc.err)
			}
			if _, err := os.Stat(filepath.Join(dir, "X.BIN")); err == nil {
				t.Fatal("X.BIN should not have been created")
			}
			if peekBGNT(c, 2, 10) == 11 || peekCHR(c, 1, 100) == 11 {
				t.Fatal("the rejected load wrote anyway")
			}
		})
	}
}

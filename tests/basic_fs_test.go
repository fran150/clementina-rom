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

func TestBasicFSExtensionsUpdateAndQueries(t *testing.T) {
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "A"), []byte("ABCDE"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "B"), []byte("xyz"), 0600); err != nil {
		t.Fatal(err)
	}
	c, step := bootClementinaToPrompt(t)
	c.SetMiaSDFolder(dir)
	lines := []string{
		`10 OPEN "A" FOR UPDATE AS #1`,
		`20 OPEN "B" FOR INPUT AS #2`,
		`30 BGET#2,V`,
		`40 SEEK#1,FPOS(2)`,
		`50 BPUT#1,65+FSIZE(2)`,
		`60 FLUSH #1`,
		`70 POKE 512,FPOS(1)`,
		`80 POKE 513,FSIZE(1)`,
		`90 POKE 514,FPOS(2)`,
		`100 POKE 515,FSIZE(2)`,
		`110 BGET#1,V:POKE 516,V`,
		`120 CLOSE #1:CLOSE #2`,
		`130 OPEN "C" FOR UPDATE AS #3`,
		`140 POKE 517,FSIZE(3)`,
		`150 BPUT#3,99:CLOSE #3`,
		`160 POKE 518,42`,
		`170 GOTO 170`,
	}
	for _, l := range lines {
		typeLine(c, step, l)
	}
	typeLine(c, step, "RUN")
	editorTickN(c, step, 2_000_000)
	for i, v := range []int{2, 5, 1, 3, 67, 0, 42} {
		if int(peek(c, uint32(512+i))) != v {
			dumpScreen(t, c.chips.mia.(videoReader))
		}
		require_eq(t, v, peek(c, uint32(512+i)), fmt.Sprint("query ", i))
	}
	data, err := os.ReadFile(filepath.Join(dir, "A"))
	if err != nil {
		t.Fatal(err)
	}
	if string(data) != "ADCDE" {
		t.Fatalf("update = %q", data)
	}
	data, err = os.ReadFile(filepath.Join(dir, "B"))
	if err != nil || string(data) != "xyz" {
		t.Fatalf("other handle changed: %q %v", data, err)
	}
	data, err = os.ReadFile(filepath.Join(dir, "C"))
	if err != nil || string(data) != "c" {
		t.Fatalf("new file: %q %v", data, err)
	}
}

func TestBasicFSExtensionsMetadataAndFree(t *testing.T) {
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "A"), make([]byte, 257), 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.Mkdir(filepath.Join(dir, "D"), 0700); err != nil {
		t.Fatal(err)
	}
	c, step := bootClementinaToPrompt(t)
	c.SetMiaSDFolder(dir)
	for _, l := range []string{
		`10 DIM Z(3)`,
		`20 FSTAT "A",S,A,D,T`,
		`30 IF S=257 THEN POKE 512,1`,
		`40 IF D>0 THEN POKE 513,1`,
		`50 FSTAT "D",Z(0),Z(1),Z(2),Z(3)`,
		`60 POKE 514,Z(1) AND 16`,
		`70 F=DISKFREE(0)`,
		`80 IF F=1073709056 THEN POKE 515,1`,
		`90 POKE 516,42`,
		`100 GOTO 100`,
	} {
		typeLine(c, step, l)
	}
	typeLine(c, step, "RUN")
	editorTickN(c, step, 2_000_000)
	for i, v := range []int{1, 1, 16, 1, 42} {
		if int(peek(c, uint32(512+i))) != v {
			dumpScreen(t, c.chips.mia.(videoReader))
		}
		require_eq(t, v, peek(c, uint32(512+i)), fmt.Sprint("metadata ", i))
	}
}

func TestBasicFSExtensionsSeek32(t *testing.T) {
	dir := t.TempDir()
	// Sparse fixture avoids allocating or writing several GiB.
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
	typeLine(c, step, "RUN")
	editorTickN(c, step, 2_000_000)
	for i, v := range []int{1, 1, 1, 1, 42} {
		if int(peek(c, uint32(512+i))) != v {
			dumpScreen(t, c.chips.mia.(videoReader))
		}
		require_eq(t, v, peek(c, uint32(512+i)), fmt.Sprint("32-bit seek ", i))
	}
}

func TestBasicFSExtensionsErrors(t *testing.T) {
	for _, tc := range []struct{ line, err string }{
		{"FLUSH #0", "ILLEGAL QUANTITY"},
		{"PRINT FPOS(0)", "ILLEGAL QUANTITY"},
		{"PRINT FSIZE(-1)", "ILLEGAL QUANTITY"},
		{"MPOKE 77824,5:PRINT FPOS(1)", "FILE I/O ERROR"}, {"FLUSH #1", "FILE I/O ERROR"},
		{"PRINT FPOS(1)", "FILE I/O ERROR"}, {"PRINT FSIZE(17)", "ILLEGAL QUANTITY"},
		{`FSTAT "MISSING",S,A,D,T`, "FILE I/O ERROR"},
		{"PRINT DISKFREE(1)", "ILLEGAL QUANTITY"},
		{"SEEK#1,-1", "ILLEGAL QUANTITY"}, {"SEEK#1,4294967296", "ILLEGAL QUANTITY"},
	} {
		t.Run(tc.line, func(t *testing.T) {
			c, step := bootClementinaToPrompt(t)
			c.SetMiaSDFolder(t.TempDir())
			typeLine(c, step, tc.line)
			vr := c.chips.mia.(videoReader)
			var screen strings.Builder
			for row := 0; row < 25; row++ {
				for col := 0; col < 40; col++ {
					screen.WriteByte(ntCell(vr, row, col))
				}
			}
			if !strings.Contains(screen.String(), tc.err) {
				dumpScreen(t, vr)
				t.Fatalf("missing %s", tc.err)
			}
		})
	}
}

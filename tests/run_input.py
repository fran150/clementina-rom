#!/usr/bin/env python3
"""Boot this checkout's ROM in the sibling Go emulator, without installing it."""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--emulator', type=Path, default=Path('/Users/fran150/development/go/clementina-6502'))
parser.add_argument('--run', default='TestBasicInput|TestBasicOverlay|TestBasicTiming|TestBasicMemory|TestBasicFSExtensions|TestEmulatedMiaFSFileInfo', help='Go test name filter')
args = parser.parse_args()
emulator = args.emulator.resolve()
subprocess.run(['make'], cwd=repo, check=True)
with tempfile.TemporaryDirectory(prefix='clementina-input-test-') as directory:
    temp = Path(directory)
    # miaKernelData captures assets.MiaKernel at package initialization, so
    # replacing the variable from inside a test is too late. Compile the new
    # ROM into the assets package using Go's source overlay instead.
    assets = emulator / 'assets/assets.go'
    source = assets.read_text()
    declaration = '//go:embed computer/mia/kernel.bin\nvar MiaKernel []byte'
    if declaration not in source:
        raise SystemExit('Emulator kernel embedding changed; update the test overlay.')
    data = ','.join(str(b) for b in (repo / 'build/kernel.bin').read_bytes())
    (temp / 'assets.go').write_text(source.replace(declaration, 'var MiaKernel = []byte{' + data + '}'))
    overlay = {'Replace': {
        str(emulator / 'pkg/components/mia/fs_info_extension_test.go'): str(repo / 'tests/fs_info_test.go'),
        str(assets): str(temp / 'assets.go'),
        str(emulator / 'pkg/computers/clementina/basic_input_phase_test.go'): str(repo / 'tests/basic_input_test.go'),
        str(emulator / 'pkg/computers/clementina/basic_overlay_test.go'): str(repo / 'tests/basic_overlay_test.go'),
        str(emulator / 'pkg/computers/clementina/basic_timing_test.go'): str(repo / 'tests/basic_timing_test.go'),
        str(emulator / 'pkg/computers/clementina/basic_memory_test.go'): str(repo / 'tests/basic_memory_test.go'),
        str(emulator / 'pkg/computers/clementina/basic_fs_extensions_test.go'): str(repo / 'tests/basic_fs_test.go'),
    }}
    # The emulator uses Go copy (memmove semantics), whereas Pico DMA reads
    # forward. Assert that the ROM's reserved memory descriptors always issue
    # disjoint, nonempty chunks, so host memmove cannot mask a hardware bug.
    commands = emulator / 'pkg/components/mia/commands.go'
    command_source = commands.read_text()
    transfer = '\treturn c.dmaTransfer(c.indexes[srcIndex].currentAddr, c.indexes[dstIndex].currentAddr, length)'
    if transfer not in command_source:
        raise SystemExit('Emulator DMA dispatch changed; update the test guard.')
    guard = """
    if srcIndex == 0xF4 && dstIndex == 0xF5 {
        src, dst := c.indexes[srcIndex].currentAddr, c.indexes[dstIndex].currentAddr
        if length == 0 || (src < dst+uint32(length) && dst < src+uint32(length)) {
            panic("ROM memory operation issued overlapping or empty hardware DMA")
        }
    }
"""
    (temp / 'commands.go').write_text(command_source.replace(transfer, guard + transfer))
    overlay['Replace'][str(commands)] = str(temp / 'commands.go')
    (temp / 'overlay.json').write_text(json.dumps(overlay))
    subprocess.run(['go', 'test', '-overlay', str(temp / 'overlay.json'),
                    './pkg/computers/clementina', './pkg/components/mia', '-run', args.run, '-count=1'],
                   cwd=emulator, check=True)

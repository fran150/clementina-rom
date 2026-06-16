# Third-Party Notice: Woz Monitor

The monitor source in this directory is the Apple-1 "Woz Monitor".

- Original author: Steve Wozniak (Apple Computer), 1976.
- First published in the Apple-1 Operation Manual (1976).
- Imported from: `https://github.com/jefftranter/6502`, subdirectory `asm/wozmon`,
  commit `668e9dbce2ef62b4509d2dc3faad459e93ee9d76` (see CLEMENTINA.md).

## License status

There is **no upstream license to vendor.** The source repository
(`jefftranter/6502`) declares no license: it has no `LICENSE` or `COPYING`
file, and GitHub reports no detected license for the repository. Under default
copyright law, "no license" means all rights are reserved by the rights holder.

The original Woz Monitor is Steve Wozniak / Apple intellectual property. It has
been reproduced widely across the retro-computing community for decades with no
known enforcement, but no formal open-source grant from the rights holder is
known to exist.

## What this means for Clementina

Clementina reuses this code under the same community-tolerated terms as every
other Apple-1 reproduction: acceptable in practice for a non-commercial,
educational homebrew project, but **not** a clean license grant.

Before any commercial distribution:

- obtain legal advice, or
- replace the monitor with Clementina-native code (the port already intends to
  rewrite the Apple-1 keyboard/display I/O against the Clementina kernel, which
  would also be the natural point to remove the original Woz Monitor code).

This notice exists precisely because there is no upstream license file to copy
in. Do not delete it without resolving the underlying status.

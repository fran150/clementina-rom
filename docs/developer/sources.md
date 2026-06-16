# Third-Party Sources and Licenses

This page is the repository-wide index of imported third-party code, its
provenance, and its license status. The repository as a whole is licensed
**GPL-3.0** (see the top-level `LICENSE`). The entries below are vendored source
snapshots with their own, separate terms.

## Summary

| Component | Location | Origin | Upstream commit | Stated license | Status |
| --- | --- | --- | --- | --- | --- |
| Microsoft BASIC for 6502 | `src/basic/` | [mist64/msbasic](https://github.com/mist64/msbasic) | `2a0bc2fe0db13f8cf1b5c40b1d5617263cdb9cb4` | BSD 2-Clause (README only) | Reconstruction under BSD-2; underlying code is Microsoft IP, not formally open-licensed |
| Woz Monitor | `src/monitor/` | [jefftranter/6502](https://github.com/jefftranter/6502) `asm/wozmon` | `668e9dbce2ef62b4509d2dc3faad459e93ee9d76` | None declared | All-rights-reserved upstream; Wozniak/Apple IP reused under community-tolerated terms |

## Microsoft BASIC for 6502

- Vendored license text: `src/basic/LICENSE`
- Import notes: `src/basic/CLEMENTINA.md`

Michael Steil's BSD-2 license covers the reconstructed, integrated source tree
and his contributors' work. Upstream provides the license only as the words
"2-clause BSD" in its README and ships no standalone license file, so the
canonical BSD-2 text is vendored at `src/basic/LICENSE` to preserve attribution
on redistribution.

The underlying 6502 Microsoft BASIC code remains Microsoft intellectual
property (the source embeds "COPYRIGHT 1977 BY MICROSOFT CO" and similar). It
has never been formally open-licensed by Microsoft. (Note: Microsoft's 2020
MIT release of GW-BASIC covers the x86 product, not this 6502 code.)

GPL-3.0 compatibility: BSD-2 code may be combined into a GPL-3.0 project; the
combined work is GPL-3.0 and the BSD notice must be retained — which `LICENSE`
now does.

## Woz Monitor

- Third-party notice: `src/monitor/NOTICE.md`
- Import notes: `src/monitor/CLEMENTINA.md`

The upstream repository declares no license, so there is nothing to vendor. The
original Apple-1 Woz Monitor is Steve Wozniak / Apple intellectual property
(1976), widely reproduced for decades without known enforcement but without a
formal open-source grant. `src/monitor/NOTICE.md` records this in full.

## Caveat

This index documents provenance and license status; it is not legal advice. The
community-tolerated reuse of both components is appropriate for a
non-commercial, educational homebrew project. Obtain legal advice before any
commercial distribution, or replace the affected components with
Clementina-native code.

## Maintenance

- When refreshing either upstream, update the commit in the table above and in
  the component's `CLEMENTINA.md`.
- If upstream adds or changes a license, update the vendored `LICENSE` /
  `NOTICE.md` and this table.
- When a component is replaced by Clementina-native code, record its removal
  here rather than silently deleting the notice.

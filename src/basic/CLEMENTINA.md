# Clementina MS BASIC Import Notes

This directory is Clementina's editable fork of `mist64/msbasic`.

Current imported upstream:

- Repository: `https://github.com/mist64/msbasic`
- Branch observed: `master`
- Commit: `2a0bc2fe0db13f8cf1b5c40b1d5617263cdb9cb4`
- Upstream date observed: 2026-04-04

This is not a pristine vendor directory. It is the source tree that Clementina
will assemble after the port begins.

There is no nested Git repository here. This is a vendored source snapshot; use
the recorded upstream commit when refreshing from `mist64/msbasic`.

- Edit files in this directory directly when changing the BASIC that builds.
- Keep Clementina-specific target glue clearly named with `clementina`.
- Prefer conditional Clementina feature flags for local extensions.
- Keep upstream import or refresh commits easy to identify in git history.
- Keep exported review patches outside `src/basic`; this directory is the
  source tree that assembles.

## Expected Clementina Target Files

The initial port will likely add files like:

```text
clementina.cfg
defines_clementina.s
clementina_extra.s
clementina_iscntc.s
clementina_loadsave.s
```

The existing upstream dispatch files such as `defines.s`, `extra.s`,
`iscntc.s`, and `loadsave.s` may need small edits to include these target
files when `CLEMENTINA` is defined.

## Refresh Notes

When refreshing from upstream, compare against the commit recorded above, merge
or copy the upstream changes into this directory, rebuild, then update this
file with the new upstream commit.

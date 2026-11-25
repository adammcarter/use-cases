# ADR 014: One spelling for every path, one dialect for every pattern

## Status

Accepted - 2026-09-25

## Context

Paths reach the core from use case files, bridge settings, markers found on disk and links transformers, and they end up inside link keys, stored results and fingerprints. Three things were underspecified, and each would have forced a breaking change once real repositories depended on it:

- **Link keys rejected spaces.** The key grammar allowed no whitespace in the file part. Reproduced: `My Tests/login test.js` produced a key the published schema rejected. Spaces in folder names are common, for example in Xcode projects.
- **Spelling was left to the file system.** `Src/app.js` resolves on a case-insensitive Mac and fails on Linux, and the two Unicode spellings of `café.js` behave the same way. One workspace could be valid on one machine and INVALID on another, and two implementations could fingerprint different bytes.
- **Globs had two dialects.** Resource globs used one tool's rules, where `**` can match zero folders, and `discovery.exclude` used another, where `*` crossed `/`.

## Decision

- A path the workspace names must match the on-disk spelling exactly, case and Unicode form included, on every operating system. A mismatch is INVALID, and the message names the on-disk spelling.
- Paths always use `/`. A file name with a control character, or that is not valid UTF-8, can't be named: marker scanning skips it with a warning, and naming it is INVALID.
- The file part of a link key is the path exactly, with any characters. A key is split at its first `@` and its last `:`. Transformers treat keys as opaque.
- One pattern dialect covers every authored path pattern: `*` within a segment, `?` one character, `**` whole segments only, everything else literal, case-sensitive.

## Consequences

- Good: nothing is left to the file system, so a workspace means the same thing wherever it is read, and fingerprints agree across implementations. The acceptance suite holds this on macOS and Linux in CI.
- Good: any file name a real repository uses can be linked.
- Cost: a path written with the wrong case, which the Mac forgave, is now an error there too. The message says the right spelling.
- Cost: no character classes or braces in patterns. They can be added later without breaking anything.

## Considered Options

- **Normalize paths (lowercase, NFC) before comparing:** forgiving, but two different files can then collide, and the stored spelling would differ from the disk.
- **Percent-encode paths inside keys:** safe, but transformers would have to decode, which violates "keys are opaque".
- **Adopt one existing tool's glob rules:** each differs at the edges (`**` at the ends, dotfiles), so a written dialect is the only stable choice.

## Confirmation

- `test_paths.py`: files named with spaces, `café` and `a@b:c` all link and verify; wrong case and wrong Unicode form are refused; a name with a control character is skipped; symlinks are never followed out; each dialect rule is checked.
- The schema hook validates every key the build produces against the widened `linkKey` pattern.

## Related Links

- `docs/design/04-workspace-structure.md` (path spelling, path patterns)
- `docs/design/05-identity-and-id-grammar.md` (link keys)
- `docs/design/09-workspace-loading.md` §19

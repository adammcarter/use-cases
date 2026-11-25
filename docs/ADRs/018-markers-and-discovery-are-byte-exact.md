# ADR 018: Markers, discovery and symlinks are defined to the byte

## Status

Accepted - 2026-09-25

## Context

Two implementations must link the same regions and hash the same bytes, or evidence written by one is stale to the other. Once evidence exists, any later fix to these rules makes every affected route stale at once. An audit found them underspecified:

- **The sentinel's id ran "to the next whitespace".** It was unclear which whitespace counted, and `<!--@use-case:a#b-->` or a notebook cell's `"# @use-case:a#b\n",` were silently dropped.
- **Nested markers contradicted themselves.** Same-line content included nested tokens, although the chapter promised nesting never changed outer content.
- **Exclusion semantics diverged.** `vendor` excluded a folder in one reading and not in another, `build/**` did or didn't match `build`, and the store was skipped only at the root.
- **Symlinks were followed or not depending on the code path.** A Windows checkout without symlink support turns a symlink into a text file, so fingerprints differed by operating system.
- **Two regions could share one link key.**
- **The default compared line endings exactly**, so LF and CRLF checkouts of one commit disagreed.

## Decision

- Every occurrence of `@use-case:` is a sentinel. `end` plus spaces or tabs makes it an end sentinel. The id is the longest run of `a-z 0-9 . # -`, less trailing `-` or `.`. A malformed sentinel warns, is not paired, and still makes its line a sentinel line.
- In line mode, the content is the whole lines between the sentinel lines, less every sentinel line. In same-line mode, it is the bytes between the tokens, less every nested token. Comment syntax around a nested same-line token stays, because no language-neutral rule can remove it. This is stated, and pinned by conformance vectors D and E.
- A pattern that matches a folder excludes it and everything in it, as in `.gitignore`. `**` is zero or more segments everywhere. The store and version-control folders are skipped at any depth.
- Symlinks are never followed. Their content is their target text, which is what git stores and what a Windows checkout writes.
- Two regions with one link key are INVALID.
- The default normalization ignores line endings. `ignore: []` asks for exact bytes.

## Consequences

- Good: HTML, notebooks, templates and minified code can all carry markers.
- Good: the rules leave nothing to the operating system, with or without symlink support. The acceptance suite shows the same fingerprints on macOS and Linux in CI (`.github/workflows/real-build.yml`).
- Cost: code on a sentinel line isn't tracked by an outer line-mode region. Authors put sentinels on lines of their own.
- Cost: changing only line endings no longer stales a route. That is intended: the behaviour didn't change.

## Considered Options

- **Remove only the token bytes in line mode as well:** tracks code on sentinel lines, but then comment decoration becomes content, and restyling a comment stales evidence.
- **Follow symlinks:** convenient on POSIX, but it gives different bytes on Windows and can read outside the project.
- **Keep exact line endings by default:** strictest, but evidence copied between Windows and macOS would never apply.

## Confirmation

- Vectors A–E in chapter 11 are reproduced by `fingerprint_vectors.py`, `openssl` and real workspaces (`test_conformance.py`).
- `test_conformance.py` covers HTML, notebook, NBSP and doubled sentinels, the same-line rule, duplicate keys, folder patterns and nested stores. It also shows that LF and CRLF checkouts agree by default.
- `test_paths.py` shows a symlink contributes its target text, identical to a plain file holding it.

## Related Links

- `docs/design/08-links.md`, `docs/design/04-workspace-structure.md`, `docs/design/11-fingerprints-and-freshness.md` §89.8
- ADRs 012, 014

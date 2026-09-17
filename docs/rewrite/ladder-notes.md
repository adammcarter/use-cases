# Swift rewrite — forward notes

Things found while porting that a LATER row must act on. Each names the row
it lands on and how it was established. Kept in the repo so they survive
across sessions.

## Row 4 — CLI

- **`plugin_root` cannot be found from a downloaded binary.** The TypeScript
  walks up from its own module, which sits inside the plugin checkout. Under
  ADR 0007 decision 3 the binary lives in a download cache with no plugin
  above it. `WorkspaceContextResolver` takes the starting point as an input;
  the CLI must decide what to pass. `plugin_root` is on no schema or
  envelope, so decision 8 is not at stake. (Found in 3c.)
- **Parse-error message wording differs** after the frozen prefix
  (`line N is not valid JSON: …`). Codes, line numbers and prefixes match.
  Accepted in 3b and 3d2 because every existing test asserts the code and the
  schema constrains `message` only to a non-empty string. The black-box
  oracle is the real check: if any oracle test reads that text, it fails here.

## Row 3e — evidence

- **The eight-concurrent-writer guarantee (decision 10) is tested here**,
  not in 3d2: `markers/appendOnly.ts` writes nothing. The real appenders are
  `evidence/appendEvidenceEvent.ts` and `showcase/jsonlLedger.ts`, with
  `durableWrite.ts`. (Found in 3d2.)

## Row 6 — release / 0.8.0

- **Freshness output embeds the tool version** (`freshness.ts` DEFAULT_TOOL).
  Every golden freshness corpus changes at the 0.8.0 bump; regenerate, don't
  hand-edit. (Found reading 3d3.)

## Row 10 — delete TypeScript

- **Every verification context hash changes.** `verificationContextHash.ts`
  hashes `pnpm-lock.yaml` by default. Deleting the TypeScript toolchain
  deletes that file, which moves every row's context hash, so all bound rows
  go stale together. Expected, and recovered by `verify --all` — but plan
  for it rather than read it as breakage. (Found reading 3d3.)
- **Three drift tests lose their source.** The embedded marker schemas are
  generated from `packages/core/src/markers/schemas/`. Once `packages/` is
  gone the generated Swift file is the source of truth and the drift test's
  input must move. (Found in 3d2.)
- **The TS-oracle corpus generators stop working** — they run the built
  TypeScript. Their committed outputs remain valid goldens; the scripts
  should be retired, not left to fail. (Implied by 3b onward.)
- **All 86 bindings point at TypeScript** tests or sources and must be
  rebound onto their Swift counterparts before `uc scan` reports coverage
  again.

## Candidate hardening (contract change — owner's call, after 0.8.0)

- `keyring.schema.json` puts no pattern on `key_id`. Without exact-byte key
  identity, a proof signed under one Unicode spelling could pick up another
  spelling's key; the port now compares exactly, but the schema still allows
  such ids. (Found in 3d2.)

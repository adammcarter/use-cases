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

- **YAML reading differs from the `yaml` package on exotic input** (found in
  3c1, all inside `Schema/YamlParser`, which wraps Yams). A quoted value with a
  raw DEL or C1 control character (U+007F–U+009F) loads in TypeScript and is a
  `parse_error` in Swift; U+0085 becomes a space; an escaped U+FEFF is dropped;
  a `null:` key reads as `"null"` where TypeScript gives `""`; surrogate-pair
  escapes are refused; a doubled leading BOM keeps one BOM in the key in
  TypeScript and none in Swift. Measured against every `.yml`/ledger file in
  this repository: none contains these characters. Known limits, not live
  bugs — revisit only if the black-box oracle or a user file hits one.
- **One leading BOM is stripped in `UseCases/`** before calling YamlParser, to
  match the `yaml` lexer. If YamlParser is ever fixed to do this itself, remove
  the duplicate in UseCases/.

- **The eight-writer ledger test must also run across processes.** Each
  evidence event lives in its own file (`evidence/by-id/<xx>/<event_id>.jsonl`),
  so writers recording DIFFERENT events never contend and cannot reveal a
  broken lock. The contention the lock exists for is several writers voiding
  the SAME evidence: with the lock, one succeeds and the rest throw
  `evidence_invalid_transition`; without it, all append and replay reports
  `evidence_sequence_conflict`. Measured with 8 node processes, 3 runs each
  way (found in 3e). Row 4 must run that void race with 8 separate
  `use-cases` processes against the binary.

- **`plan cards` needs two fallbacks in the CLI's plan-file decoder.** The
  TypeScript `renderCard` starts from `item.presentation_format ??
  defaultFormatForDeliveryKind(delivery_kind)` and `evidence_summary?.basis ??
  "(earlier run)"`, and `plan cards` reads plan files checked only for
  `schema_version` and a hash — so older or hand-edited plans rely on both.
  The Swift `PresentationPlanItem` requires the format; row 4's decoder must
  apply the same defaults. (Found in 3f1.)

## Found in 4b — init and matrix commands

- **Parser wording is masked in the CLI corpus, and nothing else.**
  `matrix upsert` puts `JSON.parse`'s own message into
  `matrix.mutation_invalid_json` (e.g. `Unexpected token 'o', "not json" is
  not valid JSON`, with V8's position, line/column and context elision); the
  port's `JSONParser` words it differently. The same holds for the core's
  `parse_error` (the `yaml` package) and `evidence_parse_error` (V8), already
  masked in the row 3 corpora. `MatrixInitGoldenCorpusTests` replaces those
  three messages on both sides and compares everything else byte for byte:
  codes, `ok`/`complete`, exit codes, the rest of stdout, stderr and every
  file. Porting V8's `JSON.parse` error formatter would close it; no test in
  `tests/` reads the text (`cli-ergonomics.test.ts` asserts the code only).
- **`matrix upsert` cannot create a file**: a `--file` that does not exist is
  `matrix.mutation_file_missing` (exit 1), so the first row of a new feature
  file cannot be added through the CLI. Ported as is.
- **`init` is a builtin, so its flags are never checked**: `uc init --bogus`
  scaffolds. A thrown scaffold failure (a `core.hooksPath` outside the repo, a
  `--repo` that is a file) is the entry-level catch's envelope, labelled by the
  leading tokens (`init`), exit 1, even in the human rendering; a blocked one
  goes to stderr in the human rendering. Ported as is.
- **The CLI entry now takes the child-process environment**
  (`CommandLineInterface.run(arguments:environment:)`, default the process's).
  Only `init`'s git calls read it; the corpus test passes one with git's global
  and system config off so a user's own `core.hooksPath` cannot leak in.
- **`JSON.parse` property order is applied to `--use-case-json` input**
  (`JavaScriptPropertyOrder`, now public in the core): index-like keys first,
  which moves schema diagnostics and the written YAML. A lone-surrogate escape
  that `JSON.parse` accepts is still refused by `JSONParser` (known 3g2 limit).

## Row 3e — evidence

- **The concurrent-writer guarantee (decision 10) is tested here** as the
  void race described under row 4, in-process; not as distinct events, which
  cannot fail. `markers/appendOnly.ts` writes nothing — the appenders are
  `evidence/appendEvidenceEvent.ts` and `showcase/jsonlLedger.ts`, with
  `durableWrite.ts`. (Found in 3d2 and 3e.)
  Measured on the Swift port: with the `mkdir` lock disabled, the void-race
  test fails 5 of 5 when run on its own, but passed once inside a full
  parallel suite run, where load serialised the writers. The test is a
  sound mutation check in isolation, not a guaranteed one under the full
  suite — another reason the cross-process version in row 4 matters.

## Found reading d4 — pre-existing TypeScript behaviour, ported as is

- **Binding and results ledgers are rewritten, not appended.**
  `markers/cli/io.ts` `appendJsonlLine` reads the whole file, adds a line and
  replaces the file via temp + rename, with no lock. Two concurrent `bind`
  (or `verify`) runs can each read the same state and the later rename wins,
  silently dropping the other's line. The file stays well-formed, so nothing
  reports it. This sits uneasily with ADR decision 10 ("concurrent writers
  never corrupt a ledger") — a lost line rather than a corrupt one. Not a
  porting fault; owner's call whether decision 10 was meant to cover it.
- **Showcase run ledgers take no lock either.** `showcase/appendShowcaseEvent.ts`
  reads the run's events, sets `sequence = count + 1` and
  `event_id = evt.<run>.<sequence>`, then appends with O_APPEND and no lock.
  Two concurrent records on one run can write two events with the same
  sequence and id. Same class as the binding-ledger race above; same owner
  decision. (Found reading 3f2.)
- **Presentation plans can fail their own published schema.** Recorded from
  the TypeScript oracle in 3f1, ported as is:
  1. every partial-input plan (`complete: false`, readiness
     `partial_due_to_integrity`) omits the `diagnostics` the schema requires
     when incomplete — this is the ordinary tolerant path;
  2. a plan that selects zero items still emits sections with empty
     `item_ids`, which the schema forbids (max_items 0, timebox too short);
  3. unchecked request values reach frozen fields — a fractional timebox, an
     empty or malformed `generatedAt` breaking the `plan_id` pattern;
  4. timebox exclusions, and eligible rows in blocked plans, are reported as
     `max_items` (the gap row 2 already recorded, wider than first thought).
  Decision 8 freezes both the schema and the behaviour, and they disagree;
  which one is right is the owner's call.
- **Showcase redaction covers observations only.** `appendShowcaseEvent.ts`
  runs `redactSecrets` on observation text and nothing else: failure-decision
  reasons, approval and rejection statements and actions reach the run ledger
  as typed. A secret pasted into a rejection reason is recorded verbatim.
  Ported as is and pinned. (Found in 3f2.)
- **WebAuthn approval never checks the relying party or origin.** Verification
  checks the challenge, the UP and UV flags and `type: webauthn.get`, but not
  `rpIdHash` or `clientDataJSON.origin`, so an assertion made for another site
  with the same credential and challenge verifies. Ported as is. (Found
  reading 3f2.)
- **Swift refuses some WebAuthn key types node accepts.** node verifies with
  whatever key type the credential's SPKI holds, ignoring the declared alg,
  so it accepts secp256k1, Ed448, RSA and DSA keys; swift-crypto cannot verify
  secp256k1 or Ed448 and the port refuses them (pinned with real signatures).
  The keyring schema allows only alg -7 and -8, so this is reachable only when
  a keyring entry's key contradicts its declared alg. The one place the port
  is stricter than the TypeScript; owner's call to accept. (Found in 3f2.)
- **Showcase dead or never-produced values:** nothing produces a `partial`
  run_outcome or a `resolution_required` approval_state; `assuranceFloor` is
  accepted and ignored (the floor always comes from the plan); a second epoch
  rewrites the same `epoch.1 -> epoch.2` transition. Ported as is. (3f2.)
- **SECURITY: `validate-ledger --base-ref` never detects a rewritten ledger
  through the CLI.** The CLI hands `git show <ref>:<path>` an ABSOLUTE ledger
  path, which git always rejects; the base-file reader treats that failure as
  an empty base, so the append-only comparison runs against nothing and passes.
  Reproduced on the shipped 0.7.0 CLI: bind a row, commit, rewrite the committed
  bindings line in place, run `uc validate-ledger --base-ref HEAD` → `ok: true`,
  no errors. `docs/security.md` names this exact command as the control for
  "the proof ledger has not been rewritten", and `scripts/use-cases-precommit.sh`
  relies on it. Ported faithfully (decision 8) and pinned by a test; fixing it
  is a behaviour change and the owner's call. (Found in 3d4a.)
- **The marker source walk does not skip `.build/` or `DerivedData/`.**
  `DEFAULT_SKIP_DIRS` covers node and web build output only. On a Swift repo
  (this one, once the TypeScript is gone) every scan reads SwiftPM dependency
  checkouts. Correctness is unaffected unless a vendored file carries marker
  text; speed is. Revisit at row 10 with the stress thresholds in decision 10.

## Found in 3g2 — capsules and skill assets, ported as is

- **A timed-out command that ignores SIGTERM records a pass.** `spawnSync`
  sends SIGTERM at the timeout and then waits for the child; one that traps
  SIGTERM and exits 0 comes back `status: 0, signal: null`, and the capsule
  verdict reads only the exit code. The timeout is invisible to the run.
  Measured with node 26 and pinned (corpus case
  `timed_out_command_that_ignores_sigterm_passes`).
- **A retry after a failed command records a pass on the failed item.** On a
  second `capsule run` with the same idempotency key, the failed command is
  not re-run (its verdict key is committed), so the item has no command
  result this time; the item-verdict pass then fires on the old observation.
  The run reports `run_outcome: passed` with `unresolved_failure_count: 1`.
  Pinned (`retry_after_a_failure_records_an_item_pass`).
- **Some spawn refusals throw halfway through a run.** A fractional
  `commandTimeoutMs` passes the runner's own 1..300000 check, and the schema
  lets a NUL into `executable`, `argv` or `working_directory`; `spawnSync`
  then throws `ERR_OUT_OF_RANGE` / `ERR_INVALID_ARG_VALUE` after `run_started`
  and every earlier step are already on the ledger. Pinned.
- **`itemHasFailure` in the item-verdict loop reads as dead by inspection**: it implies
  `itemHasCommandVerdict`. Not ported as a separate term.
- **Empty or `~` skill frontmatter crashes `validateSkillAssets`** with V8's
  `Cannot read properties of null (reading 'name')` instead of a diagnostic.
  Ported as `SkillAssetValidationError.nullFrontmatter`.
- **The capsule runner does not reuse `VerifyProcessRunner`.** That runner
  maps every start failure to exit 1 with no output and has no signal; the
  capsule result needs `exit_code: null`, the signal's name and node's
  `spawnSync <file> <ERRNO>` text. `CapsuleProcessSpawner` is libuv's
  `posix_spawn` path (PATH search on the child's environment, socket pairs,
  SIGTERM before the streams close). Row 4 may want to converge the two.
- **Divergence (not closable): output cut through a surrogate pair.**
  Truncation at 16,384 UTF-16 units can split a pair. TypeScript keeps the
  lone high surrogate (`…s\ud83d\n[truncated]`, written to the ledger as that
  escape, and hashed into the intent digest); a Swift `String` cannot hold
  one, so the port has `…s\u{FFFD}\n[truncated]` and a different ledger line
  and digest. The corpus records the result with U+FFFD and skips that case's
  ledger comparison.
- **`JSON.parse` wording** in a capsule `.json` `parse_error` is V8's own; the
  corpus comparison masks it (row 4 precedent above). A marketplace or plugin
  manifest with a lone `\uD800` escape parses in node; the port replaces such
  escapes with `�` before parsing, which keeps every observable outcome.

## Row 6 — release / 0.8.0

- **Tool version is embedded in several golden corpora** — freshness output
  (`freshness.ts` DEFAULT_TOOL) and every binding-registry event
  (`created_by.version`, 72 occurrences in the marker-commands corpus). All
  change at the 0.8.0 bump; regenerate them, don't hand-edit. (Found in 3d3,
  3d4a.)

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
- **Retired 2026-09-17:** the four `migration.*` bindings were released
  (`row_retired`) with `uc migrate test-matrix`, so 82 remain to rebind.
- **0.8.0 release notes (row 11)** must list as breaking: `uc migrate test-matrix`, the `migration` skill, the `migration-test-matrix-result` schema, the two `UCM_MIGRATION_*` codes, and the `migration` workflow mode (a config naming it stops loading). No CHANGELOG exists yet.
- **`SchemaGoldenCorpus.swift` has no committed generator** (its header points at the row 3b report); retiring the `migration` workflow mode regenerated its one changed case by re-running `validateBySchemaId` over every case, all other 61 reproducing byte for byte.

## Candidate hardening (contract change — owner's call, after 0.8.0)

- `keyring.schema.json` puts no pattern on `key_id`. Without exact-byte key
  identity, a proof signed under one Unicode spelling could pick up another
  spelling's key; the port now compares exactly, but the schema still allows
  such ids. (Found in 3d2.)

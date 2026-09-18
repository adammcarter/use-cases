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

## Found in 4c — marker commands

- **`precommit` is not a CLI command.** No `packages/cli` source names it; it
  is reached only through `scripts/use-cases-precommit.sh`, which runs
  `validate-ledger --base-ref` and `scan --ci` through the CLI and a `node -e`
  snippet. `Precommit.swift` in the core has no CLI caller, and nothing was
  ported for it. The hook script itself shells `node` and dies at row 10.
- **The corpus masks exactly these, on both sides** (`MarkerCommandsMasking`):
  every `event_id` (bind, unbind, rebind and prove mint `generateUlid` — time
  plus `Math.random` — and no flag pins it); every millisecond ISO timestamp
  other than the pinned `--generated-at` and the envelope epoch (registry
  events' `created_at` is the wall clock; a run without `--generated-at`); a
  proof's `signature.value` and non-zero `previous_entry_hash` (both cover the
  random id); run attestations and run-key contents in the cases that mint a
  key or date a record by the wall clock; the text after `is not valid JSON: `
  (V8's wording, row 4 precedent); keygen's PEM bodies, replaced in the
  generator before recording so no minted key lands in the repository.
- **`--base-ref` is ported with its bug and now pinned end to end through the
  CLI** (`validate_ledger_base_ref_misses_rewrite`): bind, commit, rewrite the
  committed bindings line, `validate-ledger --base-ref HEAD` → `ok: true`, and
  git's own `fatal: path '<abs>' exists on disk, but not in 'HEAD'` on stderr.
  `scan --base-ref` has the same shape for the proof ledger.
- **git's stderr is part of the CLI's output.** node's `execFileSync` inherits
  stderr, so `impact` outside a repository prints git's full `diff` usage text
  and `validate-ledger --base-ref` prints `fatal:` lines. `GitProcessRunner`
  now takes the environment and a `ProcessStandardErrorLog`; the dispatcher
  gives every handler one and emits it as stderr even when the handler throws.
  The corpus records git 2.54's wording as expected bytes, so a different git
  fails those cases until the corpus is regenerated — a regeneration trigger,
  like the tool version in the row 6 note.
- **Every `process.env` read is threaded from the CLI entry's environment**:
  the run key's home (`HOME`, `UC_RUN_KEY_FILE`), `--signing-key-env`,
  `GITHUB_*` producer fields, CI authority detection and
  `UCM_ALLOW_UNSAFE_VERIFICATION`. Known limit: `VerifyProcessRunner` sets no
  environment, so the verifier child inherits the real process's (the test
  host's in the in-process corpus, the shell's through the binary). That is
  faithful — `spawnSync` inherits too — but the corpus cannot detect an
  environment divergence in the verifier child.
- **Divergence — key material checks are ed25519-only.** node's
  `createPublicKey`/`createPrivateKey` accept RSA, EC and other keys (failing
  later, at signing or verification) and word each failure with OpenSSL's own
  detail. The port refuses anything but an ed25519 PEM up front and always
  gives the decoder detail `error:1E08010C:DECODER routines::unsupported`,
  which is node's text for non-key input (the only malformation the corpus
  records). An RSA `--public-key` is `public_key.invalid` in Swift and a later
  signature failure in node.
- **Divergence — fractional line flags.** `--line 2.5` is a finite number, so
  the TypeScript passes 2.5 to the core (where `splice` truncates it); the
  core port takes whole lines, so the CLI drops a fractional value as absent
  (`BIND_LINE_REQUIRED` / `BIND_SPAN_REQUIRED`). Not in the corpus.
- **Thrown core errors map to node's codes where node has one** (errno for
  files, the matrix loader's own codes) and to `internal_error` for the plain
  `Error`s (git, canonical JSON, signing, verifier spawn). node's spawn
  `ERR_*` codes for a verifier argv it rejects are not reproduced (`internal_error`).
- **Human rendering: `TrustRenderer`** ports `trustRender.ts` whole, including
  `showcase.status` and the approval-request object view, which nothing
  reaches until 4e. Only `scan`, `verify`, `impact` and `recover` are pinned by
  this corpus; 4e must add corpus cases for the other two.
- **Cannot be pinned in-process: paths relative to the working directory for
  WRITES.** `--bindings`, `--out` and friends resolve against `process.cwd()`;
  the in-process corpus test cannot change directory, so only a relative READ
  that fails (`scan --public-key missing.pem`) is recorded. The by-hand check
  covers relative `--repo .`.

## Found in 4d — evidence commands

- **The CLI is async from the entry down.** `EvidenceAppender.append` is
  `async` (the lock polls through the injected clock), and no legal bridge
  makes it synchronous — a semaphore would block the very cooperative pool the
  poll suspends on. So `CommandHandler`, `CommandDispatcher.run`,
  `CommandLineInterface.run` and `UseCasesCommand` (now
  `AsyncParsableCommand`) are all async; the 4a–4c corpora replay through
  `await` and are unchanged otherwise. `evidence status` stays a synchronous
  handler, because replay is synchronous. The corpora only ever await
  `CommandLineInterface.run` in process, so the new entry (`UseCasesMain.main()
  async`, and `ExitCode` thrown out of an async `run()`) is proven through the
  BINARY: `version`, `version --json`, `matrix validate` on a missing
  workspace, an unknown command and `evidence status` on a missing workspace
  are byte-identical to node with the same exit codes (0, 0, 2, 2, 2).
- **The eight-process void race is pinned** (`EvidenceVoidRaceTests`, row 4's
  standing item): eight `use-cases` processes void the SAME evidence, exactly
  one appends, seven answer `evidence_invalid_transition` (exit 6) and replay
  afterwards is clean. Two things had to be right for it to be a real check:
  every process is STARTED before any is waited for, and the history is seeded
  with 400 extra ledgers so a replay takes tens of milliseconds — wider than
  the launch stagger. Without the seeding the mutation (`withAppendLock`
  calling its work directly) passed 2 of 3 attempts, the same luck the row 3e
  note records in-process; with it, all eight appended and replay reported
  `evidence_sequence_conflict` on 3 of 3. The same race through eight
  `node dist/uc.js` processes behaves identically (1 winner, 7 losers, clean
  replay, 3 of 3 runs).
- **The losers' code depends on the order of two checks.** `voidUnderLock`
  tests the aggregate's status before the idempotency key, and all eight
  writers derive the SAME default key `cli:void:<id>:<head>`. Reversing those
  checks would turn the seven refusals into seven silent `appended: false`
  successes, so the race test asserts the code as well as the count.
- **A void's `intent_digest` cannot be compared across runs** and is masked on
  both sides of the corpus: the void intent's target is the evidence id itself,
  which is a random uuidv7. A recorded event's digest does not cover the id and
  is compared byte for byte. The by-hand node/Swift comparison shows exactly
  this one difference and nothing else.
- **CLOSED in 4e — a performed run whose output passes `spawnSync`'s 1 MiB
  `maxBuffer`.** As found in 4d: node kept the 64 KiB read that crossed the
  limit (1 MiB + 65,536 bytes, digest `sha256:cd2d309f…`) and the port kept the
  8 KiB one its socket pair delivered (1 MiB + 8,192 bytes,
  `sha256:94896abb…`). The cause was the socket, not the loop:
  `CapsuleOutputCapture` already read in 64 KiB chunks, but macOS gives a
  `socketpair` 8 KiB (`net.local.stream.recvspace`), which caps every `read`
  at 8 KiB. `CapsuleProcessLaunch` now sets `SO_RCVBUF` and `SO_SNDBUF` to
  64 KiB on both ends of both pairs, and a pair that cannot take them fails the
  start rather than degrading silently. Pinned twice: `CapsuleProcessSpawnerTests`
  compares node's own kept bytes and digests for four scripts (over the limit on
  stdout, on stderr, on both, and exactly at it), and the evidence corpus now
  records the over-limit `--perform` run it used to avoid
  (`perform_output_past_the_buffer`, 1 MiB + 65,536 bytes,
  `sha256:cd2d309f…`). Only a writer that fills the buffer faster than it is
  read can be pinned: `head -c … /dev/zero | tr` is one, and `/usr/bin/yes` is
  not — node's own kept bytes move run to run for it (1,081,080 / 1,105,650 /
  1,113,840 over five runs), because how much a read delivers is then the
  child's timing, not the chunk size. `perform_large_output_under_the_buffer`
  (1,000,000 bytes) is unchanged.
- **Divergence — the performed child's environment order.** `spawnSync`
  inherits `process.env` in its own order; the port sorts the CLI's environment
  by key when it builds `environ`. Only a command that prints its whole
  environment could see it, and nothing in the corpus does.
- **`--perform` redacts the summary only.** `appendEvidenceEvent` redacts the
  summary before digesting it, so a secret in the argv is recorded verbatim in
  `method.executable`, `method.argv` and (through the output digest) the
  idempotency key. Pinned as is (`perform_secret_in_argv_is_kept`); same class
  as the showcase-redaction note below.
- **A performed run is identified by its output.** The default idempotency key
  is `cli:run:<row>:<stdout digest>:<exit>`, so re-running a command whose
  output changed writes a NEW aggregate rather than deduplicating, and
  re-running one whose output is identical is deduplicated even if the failure
  was intermittent. Pinned (`perform_changed_output_is_a_new_record`,
  `perform_idempotent_repeat`).
- **`record` throws where `void` catches.** The TypeScript `record` handler has
  no catch, so a damaged history, a reused key or a lock timeout comes out of
  the entry-level catch as exit 1; `void` maps its own failures (stale head 1,
  damaged history 3, anything else 6). Ported as is — the exit codes differ for
  the same underlying error.
- **`evidence_parse_error` wording is masked, as in rows 3 and 4b**: V8's
  `JSON.parse` message (`Unexpected token 'o', "not json" is not valid JSON`)
  against the port's (`Unexpected token in JSON at position 1.`). The code, the
  `source_path` naming the line and everything else are compared.
- **Not in the corpus: a lock held by someone else.** A pre-existing
  `evidence/.locks/append.lock` directory makes every appender wait the full
  30 seconds, which is too slow for a 106-case corpus; the corpus instead pins
  the immediate `evidence_lock_timeout` a non-EEXIST `mkdir` failure gives (an
  unwritable `.locks`, exit 1 for record and 6 for void).
- **The Debug binary now lands in `DerivedData/use-cases-*`**, not
  `DerivedData/UseCasesCLI-*`: adding the executable to the test target's
  dependencies (so the race test always has a binary) moved Xcode's derived
  data to the package name. The stale `UseCasesCLI-*` copy is still there and
  is NOT rebuilt — check the mtime of the one you run. (In 4e the freshest was
  `UseCasesCLI-*` again, because that is the workspace Xcode had open; the note
  stands as "check the mtime", not "prefer one path".)

## Found in 4e — plan, capsule, showcase and approve-run

- **Nothing in the CLI answers `cli_not_yet_ported` any more.** All 44 commands
  run, so `NotYetPorted`, the `unportedPath` initialiser and `isPorted` are
  gone; `CommandRegistryTests` now runs every declared command against a
  workspace that is not there and asserts none of them refuses as unported.
  Row 5's MCP binary is a separate executable and is unaffected.
- **Three CLI-facing enums had to widen, because the TypeScript passes an
  unrecognised flag value straight through to the ledger.** `showcase
  record-verdict --verdict maybe`, `--actor robot` and `showcase decide
  --decision waive` are all recorded as given by node (measured), so
  `ShowcaseVerdict`, `ShowcaseActorType` and `ShowcaseFailureDecision` each
  gained an `other(String)` case with a hand-written `RawRepresentable`. Only
  `user` and the four known decisions are ever compared in the core, so nothing
  else changed. Without this the port would have had to invent a refusal the
  TypeScript does not have.
- **`plan cards` reads plan files through its own lenient decoder**
  (``PlanCardItem``), as the row 3f1 note required: `presentation_format ??
  defaultFormatForDeliveryKind(delivery_kind)` and `evidence_summary?.basis ??
  "(earlier run)"` are both applied, and BOTH are pinned by corpus cases whose
  plan files are the real plan with that member deleted and the content hash
  recomputed. Where the TypeScript would instead read a property of
  `undefined`, the port raises V8's own message — `Cannot read properties of
  undefined (reading 'emoji')` for a format or delivery kind the tables do not
  know, `(reading 'length')` for an absent `resolved_steps` — and the reads are
  format-specific, so `Reviewing` never looks at `resolved_steps` and
  `Explaining` looks at it only when there are no expected observations. The
  echoed `presentation_format` is the value AS READ: absent stays absent.
- **`showcase request-approval` returns the minted request itself**, not a
  result envelope: no `ok`, no `complete`, no `context`. Its human rendering is
  `TrustRenderer.renderApprovalRequest`, and `showcase status`'s is
  `showcaseStatusLines` — the two renderings the 4c note left unpinned. Both
  are now corpus cases (`request_approval_text`, and the `approved by user ·
  tier trusted_host_user_presence` line in `signed_approval_text_and_status`).
- **A run is user-required only under `approval_policy: mode: predefined` with
  a `user` approver.** `mode: ask` makes an item `user_led` in presentation and
  changes nothing about approval, so a corpus that only used `none` and `ask`
  would never exercise the F3 gate. The showcase corpus has a row with a
  predefined user requirement, which is what makes
  `showcase.user_required_approval` (agent refused),
  `showcase.trusted_user_confirmation_required` (no token),
  `showcase.approval_nonce_burned`, `showcase.approval_decision_mismatch` and
  `showcase.approval_assurance_too_low` reachable.
- **`approve-run` signs with the DEFAULTED assurance method.** The TypeScript
  passes `assuranceMethodFlag ?? "os_presence"` to `signApprovalToken`, so a
  token minted without `--assurance-method` still carries
  `assurance_method: os_presence` and its tier — and that tier is what meets a
  plan's floor. Passing the flag through as `undefined` instead produces a
  token that verifies as `untrusted_automation`.
- **Divergence — `approve_run.sign_failed` wording for key material.** node
  lets OpenSSL's own message through `createPrivateKey`; the port refuses
  anything but an ed25519 PEM up front (the row 4c divergence) and reports
  node's decoder text for non-key input,
  `error:1E08010C:DECODER routines::unsupported`, which is what node gives for
  the only malformation the corpus records.
- **Key material is minted per case, never committed.** Each showcase case that
  signs runs a `keys` step: the generator and the Swift replay each mint their
  OWN ed25519 pair (as `tests/blackbox/showcase-flow.test.ts` does), so every
  PEM body, every `signature.value` and the `intent_digest` of every
  `approval_recorded`, `approval_rejected` and `approval_nonce_burned` event are
  masked on both sides — those intents carry the token, nonce included. Every
  other event's digest, and every approval state, tier and capture method, is
  compared byte for byte. The mask matches `approval_[a-z_]+`, which is exactly
  those three event types today; widen the note (and check nothing else is
  swallowed) if a fourth `approval_*` event type is ever added, because its
  digest would be masked silently and stop being compared.
- **Pinning `--idempotency-key` pins the whole ledger.** A showcase run id is
  `run.<key>` and its events are `evt.run.<key>.<n>`, so the showcase corpus
  needs no id masking at all. The one place a clock still reaches the output is
  `capsule run` without `--idempotency-key`, whose derived key ends in
  `Date.now()`: that epoch is masked in the plan/capsule corpus (delimiters
  kept), and the intent digests of those events do not cover the key.
- **The unknown-flag check reads EVERY command's flags.** `capsule list --all`
  and `capsule plan --mode showcase` are accepted and ignored, because `--all`
  and `--mode` are declared by `verify` and `workflow set-mode`; only a
  spelling no command declares (`--everything`, `--capsuls`) is
  `cli_unknown_flag`. Pinned as is, both ways
  (`capsule_list_flag_declared_by_another_command`).
- **`JSONWriter.encodePretty` is new**, for the two places a human-readable
  JSON file is written: the token `approve-run --out` writes and the keyring a
  test mints. The wire form is untouched.
- **swiftlint's `single_line_closure_body` false-fires on regex literals, and
  the cure is placement.** The rule's pattern is
  `\{\s*[^}\n]*\([^}\n]*\)[^}\n]*\}`, and `\s*` crosses newlines, so an
  opening brace whose FIRST statement is a regex literal containing both a
  group and `[^{}]` matches: the `(`, the `)` and the `}` of the character
  class are all on that one line. Putting any non-regex statement immediately
  after the brace (`var masked = text`) breaks the span and needs no change to
  the pattern being masked. Both masking files do this.
- **Cannot be pinned: a plan file whose `use_case_title` is not a string.** The
  TypeScript's `?.trim()` raises on a number; the port's decoder reads a
  non-string title as absent, which falls back to the id. No corpus case, and
  no plan the CLI writes can hold one.

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

## Row 5 — MCP server

- **Decision 7 and decision 8 collide, and the wire won.** The MCP Swift SDK's
  `Server` actor encodes every response with `JSONEncoder` and
  `.sortedKeys` (`Sources/MCP/Server/Server.swift:371-372`, on a private
  `send`), so it cannot emit the frozen envelope key order, the declared
  schemas' property order, or `structuredContent` as the TypeScript writes
  them. Three more things it cannot express:
    - `MCP.Tool` has no `command` or `mutability` member — only `_meta` — and
      the TypeScript emits both on every one of the 19 descriptors, `command`
      second and `mutability` last.
    - `initialize` is answered once: a second one is refused
      `-32600 "Server is already initialized"` (`Server.swift:928`). The
      TypeScript answers every one, and the black-box helper
      (`tests/helpers/mcp-server.ts`, `capabilities()`) sends a second
      handshake and reads its capabilities.
    - the protocol version is negotiated (`Version.negotiate`), so a client
      asking for `2024-11-05` is answered `2024-11-05`; the TypeScript always
      states `2025-11-25`.
  The port therefore uses the SDK for what it can carry — `StdioTransport`,
  which frames newline-delimited messages on stdin and stdout with the
  non-blocking partial-write retry a pipe needs — and writes the response
  bytes itself through `JSONWriter`. Decision 8 (contract freeze) outranks a
  library choice, and the brief's own "JSONValue/JSONWriter, never
  JSONEncoder" says the same. **Owner question:** is "on the MCP Swift SDK"
  satisfied by using it as the transport, or should the wire contract move to
  the SDK's shape at 0.8.0?
- **The SDK pins nothing for `swift-docc-plugin`** (`branch: "main"` in its
  own manifest), in a repo where every dependency is `exact:`. Nothing of
  ours builds documentation, so it is inert, but it is in `Package.resolved`.
- **Divergence (deliberate): a core failure inside a resource read.** The
  TypeScript lets it escape the `line` handler, which ends the process —
  a damaged ledger kills the server. The port reports `-32603` with the core
  error's message instead. Every oracle and corpus case is unaffected; no
  recorded case reaches it.
- **The gate order in `callMcpTool` is observable.** `allow_write !== true` is
  checked BEFORE the server's write mode, so a read-only session that asked
  for the write is told `mcp.server_write_mode_required` and one that did not
  ask is told `mcp.write_mode_required`. Two codes, and which one answers says
  which lock refused.
- **A refusal envelope carries the SERVER's working directory as its roots**,
  not the workspace: `errorEnvelope` passes no roots and the factory defaults
  them to `process.cwd()`. The Swift refusal takes them from
  `McpEnvironment.workingDirectory` so an in-process replay reproduces it.
- **A relative `repo` resolves against the server's working directory**
  (`resolve(process.cwd(), repo)`), and `data_root` against the REPO — not
  against the working directory as the CLI resolves it.
- **`evidence_record` is the only appending tool with no timestamp argument.**
  Its `recorded_at`, `captured_at` and UUIDv7 event id come from the clock, so
  the corpus normalises those three (and the ledger shard derived from the
  uuid) for that case alone, naming them in the case's own `clock_fields`.
  Every other appending tool is given an explicit `recorded_at` and
  `idempotency_key`, and its ledger ids reproduce byte for byte
  (`run.corpus_start`, `evt.run.corpus_start.1`...).
- **`showcase_start` reads the clock twice.** `generated_at` and
  `freshnessEvaluatedAt` are two separate `new Date().toISOString()` calls in
  the TypeScript; the port calls its clock twice too, so a caller who pins
  `generated_at` pins both and one who does not gets whatever the two calls
  give.
- **`uc://schemas/{name}` leaves `schema` out when it did not load**, because
  `JSON.stringify` drops an undefined member rather than writing null. Only
  reachable if an embedded schema fails to load.
- **The binding resource orders rows and slugs by `localeCompare`**, not by
  code unit, while `binding_slugs` within a row uses the default
  `Array.prototype.sort`. Both are reproduced.
- **`showcase_request_approval` still suggests `uc approve-run`**, not
  `use-cases approve-run`: the rename (decision 4) has not reached the MCP
  prompt text or this suggested command, and the same is true of every `uc`
  in the four prompts. Frozen as-is for the port; row 6 or the rename row
  owns it.

## Row 6 — release / 0.8.0

- **Tool version is embedded in several golden corpora** — freshness output
  (`freshness.ts` DEFAULT_TOOL) and every binding-registry event
  (`created_by.version`, 72 occurrences in the marker-commands corpus). All
  change at the 0.8.0 bump; regenerate them, don't hand-edit. (Found in 3d3,
  3d4a.)

### Built in row 6 (pipeline ready, never fired)

- **`.github/workflows/release.yml`** builds each package thin for the one
  published platform (`swift build -c release --arch arm64`) on `macos-15`,
  archives both executables per platform, writes `SHA256SUMS` over the archives
  and attaches them plus the sums with `gh release create/upload`. Triggers are
  a `v<semver>` tag push and `workflow_dispatch` only — there is no `branches:`
  key, so a branch push can never publish while decision 9 stands, and a
  hand-dispatched run defaults to `--draft`.
- **Apple Silicon only, decided by the owner 2026-09-17.** Every universal
  build printed `warning: The x86_64 architecture is deprecated for your
  deployment target (macOS 27.0). You should update your ARCHS build setting to
  remove the x86_64 architecture.`, so the x86_64 asset was retired rather than
  shipped stale. The published platform list now lives in exactly two places —
  `PUBLISHED_PLATFORMS` in `bin/use-cases-bootstrap` and the workflow's `for
  platform in …` loop — and
  `release.distribution.release_publishes_checksummed_assets` fails unless both
  are exactly `macos-arm64` and neither file mentions the other architecture.
  Both kept their loop/list shape, so adding a platform back is one line each.
- **No `lipo` slicing, because there is nothing to slice.** A single `--arch
  arm64` build is already a thin Mach-O; building universal and cutting back
  down would be a round trip whose only contribution is a way to get it wrong.
  `lipo -info` stays as a CHECK — the workflow greps for
  `Non-fat file.*architecture: <arch>`, so a universal product can never slip
  out under a per-platform asset name.
- **Platform resolution stayed meaningful with one platform.** `Darwin/arm64`
  is the only mapped case, so an Intel Mac and a non-Mac both fall to the
  refusal, which names what it found and the published list: `no published
  binary for Darwin/x86_64.` / `Published platforms: macos-arm64.` Covered by
  `release.distribution.failed_download_says_what_to_do.edge_unsupported_platform_is_refused_before_any_download`,
  which drives both cases through a PATH-stubbed `uname`.
- **`USE_CASES_PLATFORM` is still the seam a second platform gets tested
  through.** Forcing a slug no release publishes is refused at the checksums
  (`the checksums published for release v… do not list use-cases-…-macos-x86_64.tar.gz`),
  not exec'd as the wrong slice — row 2's edge scenario.
- **The bootstrap suites are Apple-Silicon-gated, because `ci.yml` runs on
  `ubuntu-latest`.** `vitest.config.ts` includes `tests/**/*.test.ts` with no
  platform filter, and the stand-in helper's `hostPlatform()` throws off
  darwin/arm64 — so without a gate the ~24 download tests would THROW on the CI
  runner, not skip. The three bootstrap suites and the two release-workflow
  tests that drive a real download are `skipIf(!canRunBootstrap)`; the
  workflow's text assertions still run everywhere. Measured by forcing the flag
  false: `6 files passed | 3 skipped`, `25 passed | 24 skipped`, nothing failed.
  **The consequence is deliberate and must not be forgotten:** those four rows'
  script verifiers exit 0 on Linux having asserted nothing, so a green
  `uc verify` from a Linux runner does not prove `release.distribution.*`. Same
  honest edge as scenario-conventions §8c; the rows are provable on Apple
  Silicon only.
- **`runs-on: macos-15` is never exercised by this row.** The release-workflow
  test only asserts `/^macos-/`, deliberately, so the label does not rot the
  suite — but check it against GitHub's current runner labels before the
  workflow is fired for the first time.
- **The products live at `.build/out/Products/Release`** under the Swift 6.2
  build system, not `.build/apple/Products/Release`. The workflow asks
  `swift build … --show-bin-path` rather than hardcoding either.
- **The naming scheme is `use-cases-<version>-<os>-<arch>.tar.gz`** inside
  `…/releases/download/v<version>/`, each archive carrying BOTH executables, so
  one download serves `use-cases` and `use-cases-mcp`. Only
  `tests/plugin/release-workflow.test.ts` stops the publisher and the
  downloader drifting apart on the name, the platform list or the tag.
- **`bin/use-cases-bootstrap` needs no edit at the 0.8.0 bump.** It reads the
  version from `.claude-plugin/plugin.json`, so bumping the manifest points it
  at the new release. `USE_CASES_VERSION`, `USE_CASES_RELEASE_BASE_URL`,
  `USE_CASES_CACHE_DIR` and `USE_CASES_PLATFORM` override version, release
  root, cache and platform; the first three are what makes the suite hermetic.
- **SHA256SUMS authenticates transport, not provenance** — accepted by the
  owner 2026-09-17. It is fetched from the same release as the archive, so
  anyone who can write the release can write both. That is exactly what
  decision 3 asks for; a signed manifest would be a contract change, not this
  row.
- **At 0.7.0 `bin/use-cases` failed by design — superseded by row 7.** While
  row 6 stood, `bin/use-cases` went straight to the bootstrap and got
  `release v0.7.0 does not carry use-cases-0.7.0-macos-arm64.tar.gz`. Row 7 put
  `bin/use-cases-runtime` in front of it, so at a pre-0.8.0 version the command
  runs the committed bundle instead and that refusal is now only reachable by
  forcing a Swift-era version. The bootstrap's own failure hint moved with it:
  it names `node <root>/dist/uc.js` (or `dist/uc-mcp.js`), not `bin/uc`, because
  `bin/uc` now resolves to the same place the failure came from.
- **The Apple-Silicon-only decision adds nothing to the 0.8.0 bump list.** It
  touches no file that embeds the version, so the list below is unchanged by
  it; the platform list and the version bump are independent edits.
- **What the 0.8.0 bump has to touch** (row 11), measured 2026-09-17:
  `package.json`, `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`,
  `packages/{core,cli,mcp}/package.json`, `packages/core/src/version.ts`
  (`UCM_VERSION`), `UseCasesCore/Sources/UseCasesCore/Foundation/ProductVersion.swift`
  and its `ProductVersionTests`. Then regenerate — do not hand-edit — the four
  generators `UseCasesCore/Scripts/generate-{markers-ledger,marker-commands,
  verify-prove,scan-impact}-corpus.mjs` (each pins `0.7.0` in its fixtures) and
  the nine golden corpora that embed the version:
  `UseCasesCore/Tests/…/Markers/{MarkersLedgerGoldenCorpus,MarkersFreshnessGoldenCorpus}.swift`,
  `…/Markers/Commands/{MarkerCommandsGoldenCorpus,VerifyProveGoldenCorpus,ScanImpactGoldenCorpus}.swift`,
  `…/Skills/SkillsGoldenCorpus.swift`,
  `UseCasesCLI/Tests/…/Entry/{DispatchGoldenCorpus,MarkerCommandsGoldenCorpus}.swift`
  and `UseCasesMCP/Tests/…/Server/McpGoldenCorpus.swift`
  (`SchemaGoldenCorpus.swift` has no generator — see row 10's note). Two prose
  mentions of "removed in 0.7.0" (`tests/helpers/uc-binary.ts`,
  `tests/blackbox/agents-roster.test.ts`) are history and stay.
  `.use-cases/bindings.jsonl` carries `0.7.0` in 75 past `created_by.version`
  entries: it is append-only and must NOT be rewritten.
  Row 7 adds nothing to this list — `bin/use-cases-runtime` reads the manifest
  version — but if the first release to publish Swift assets is ever NOT 0.8.0,
  `FIRST_SWIFT_RELEASE` in `bin/use-cases-runtime` is the one place that has to
  move, and its test fixtures assume a stand-in version above it.

## Row 7 — the plugin cut-over

- **The cut-over is the wiring, and the version is the switch.** Every host
  manifest now names the plugin's own entry point
  (`bin/use-cases-mcp`), and `bin/uc`, `bin/use-cases` and `bin/use-cases-mcp`
  all exec `bin/use-cases-runtime`, which picks the runtime from the plugin
  version alone: `>= 0.8.0` goes to `bin/use-cases-bootstrap` (download, verify,
  exec, no fallback out of that path), below it runs the committed Node bundle.
  So no manifest, hook, skill or doc changes when 0.8.0 publishes — the version
  bump is the whole flip, and `bin/use-cases-runtime` needs no edit either
  because it reads `.claude-plugin/plugin.json` exactly as the bootstrap does.
- **Why a version branch and not a fallback.** Row 6's rule — no automatic
  fallback to the Node bundle, because it would mask a missing release — is
  intact and is why the branch is taken BEFORE any download: a release that
  should carry the assets and does not still exits 1 with nothing cached. A
  failure-triggered fallback would have broken that rule; a version-triggered
  branch does not, because it never sees a failure. Measured both ways in
  `tests/plugin/runtime-resolver.test.ts`.
- **`FIRST_SWIFT_RELEASE` is the one constant, and it is compared, not listed.**
  An exact list of pre-Swift versions (`0.7.0`) was rejected: an unanticipated
  pre-0.8.0 version — a bundle hotfix, say — would fall off the list and try to
  download, breaking every installed plugin. A `>=` comparison has only the two
  failure modes we want. `sort -V` is not assumed: three integers are compared
  in bash after the prerelease suffix is stripped, so `0.8.0-rc1` is Swift-era.
  An unparseable version is refused rather than guessed — either guess would
  run something.
- **`bash <script>`, not the script as the command, on every host.** Claude and
  Copilot read `{"command": "bash", "args": ["${CLAUDE_PLUGIN_ROOT}/bin/use-cases-mcp"]}`:
  `${CLAUDE_PLUGIN_ROOT}` interpolation in an `mcpServers` **`args`** entry is
  proved — the old manifest interpolated it there and was observed live — and is
  NOT proved in `command`, so the variable stays in `args` and only the
  interpreter changes. (`hooks.json` also uses the variable, but that is a
  different code path and is not the evidence for this one.) Codex keeps the shape it was observed working with — a relative script
  under `cwd: "."` — with `node ./dist/uc-mcp.js` swapped for
  `bash ./bin/use-cases-mcp`. OpenCode registers `["bash", <abs path>]`. One
  shape for four hosts, and none of them depends on the exec bit surviving the
  host's install.
- **Every link execs.** `bash bin/use-cases-mcp` -> `exec bin/use-cases-runtime`
  -> `exec node dist/uc-mcp.js` (or `exec <cached binary>`). A missing `exec`
  would leave a shell holding the server's pipes and swallowing its signals, so
  it is pinned twice: a stand-in executable that prints its own `$$` must report
  the spawned pid, and `ps -o comm=` on a live server must name `node` or
  `use-cases-mcp`, never `bash`.
- **Three assertions changed shape, none weakened.** (1)
  `tests/plugin/release-workflow.test.ts`'s "asks for the plugin's own version
  by default" now drives `entry: "bootstrap"` instead of `bin/use-cases`: it
  asserts the same thing at the layer that still owns it, because the wrapper
  now sends 0.7.0 to the bundle. (2) `tests/plugin/bootstrap-failures.test.ts`
  asserts the hint names `dist/uc.js` and that the named path EXISTS, which the
  old `bin/uc` assertion did not check. (3) The manifest tests gained
  `not.toContain("dist/uc")` and an executable-bit check on the wrapper.
- **The repo's own matrix is snapshotted by three Swift corpora**, so adding
  `use-cases/plugin/runtime.yml` and editing `install.yml` moves them:
  `UseCasesRepositoryMatrixCorpus` (the whole `use-cases/` tree),
  `PresentationGoldenCorpus` (rows feed the planner) and `SkillsGoldenCorpus`
  (it snapshots `.claude-plugin/plugin.json` verbatim, so ANY manifest edit
  moves it). Regenerate with `generate-{use-cases,presentation,skills}-corpus.mjs`
  after `pnpm --filter @adammcarter/use-cases-core build`; never hand-edit.
  `McpGoldenCorpus` is NOT affected — its only `dist/uc-mcp.js` is in the header.
- **The row 7 tests are Apple-Silicon-gated in the same way row 6's are, but
  less of them.** Only the three scenarios that drive a real download are
  `skipIf(!canRunBootstrap)`; the unparseable-version refusal and every
  committed-bundle scenario run everywhere. So on a Linux runner
  `plugin.runtime.pre_swift_versions_run_the_committed_bundle` is fully proved
  and `plugin.runtime.release_versions_run_the_verified_swift_binary` is proved
  only in part — the same honest edge as `release.distribution.*`.
- **What the 0.8.0 bump gains from this row: nothing.** `bin/use-cases-runtime`
  reads the manifest version, so the bump list below is unchanged. What the bump
  DOES do, the moment it lands, is move every host onto the downloaded binary —
  so 0.8.0 must not be tagged before its release workflow has actually published
  the assets, or the installed plugin fails at the first command.
- **Left alone deliberately.** `.githooks/pre-commit`, `.githooks/pre-push` and
  `packages/core/test/init/scaffold-sample.test.ts` run `node dist/uc.js`: they
  are this repo's own dev tooling, not a host surface, and row 10 owns them with
  the rest of the TypeScript. `tests/helpers/{uc-binary,mcp-server}.ts` keep
  their Node defaults with `UC_BIN`/`UC_MCP_BIN` as the seam — the oracle's
  default is row 10's to move, not this row's. The `uc` command name is
  untouched: row 8 does the rename, and the session-start bootstrap still names
  `bin/uc`.
- **The four hosts' `edge_live_session` observations are now STALE, and this is
  an owner item.** They were performed on 2026-09-16 against
  `{"command": "node", "args": ["${CLAUDE_PLUGIN_ROOT}/dist/uc-mcp.js"]}`. The
  `command` is now `bash`. The by-hand proof simulates each host exactly — the
  manifest's own command and args, from a clean shipped copy, four hosts, the
  server answering 19 tools and `ps` naming the server rather than `bash` — but
  it cannot show that the HOST accepts `command: "bash"`. Both are bare PATH
  lookups, so the risk is low; the re-observation (install on Claude and
  Copilot, start a session, list the MCP tools) is still owed. Same "ready but
  not fired" shape as row 6.
- **Codex's live MCP observation is still unmade** (the usage cap of 2026-09-16);
  `edge_live_mcp_not_yet_observed` stays a scenario the row does not claim.
  Changing the manifest does not turn it into an observation.

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
  (`row_retired`) with `uc migrate test-matrix`, so 82 remained to rebind; row 7
  added two more (both on `tests/plugin/runtime-resolver.test.ts`), making 84.
- **One of those two has no Swift counterpart and must be RETIRED, not rebound.**
  `plugin.runtime.pre_swift_versions_run_the_committed_bundle` pins the
  committed-bundle branch of `bin/use-cases-runtime`; deleting `dist/` deletes
  the behaviour. Retire the row and the resolver's Node branch together — at
  which point `bin/use-cases-runtime` is a one-line exec into the bootstrap and
  can be folded away entirely, and `bin/use-cases-bootstrap`'s `fallback_hint`
  (which names `dist/uc.js`) goes with it.
- **0.8.0 release notes (row 11)** must list as breaking: `uc migrate test-matrix`, the `migration` skill, the `migration-test-matrix-result` schema, the two `UCM_MIGRATION_*` codes, and the `migration` workflow mode (a config naming it stops loading). No CHANGELOG exists yet.
- **`SchemaGoldenCorpus.swift` has no committed generator** (its header points at the row 3b report); retiring the `migration` workflow mode regenerated its one changed case by re-running `validateBySchemaId` over every case, all other 61 reproducing byte for byte.

## Row 8 — the hard rename (`uc` → `use-cases`)

- **This file, `docs/adr/`, `docs/acceptance/0.3.0/`, the two `.use-cases/`
  ledgers, `showcase-runs/` and `tests/fixtures/backcompat/` are RECORDS and
  were deliberately left saying `uc`.** ADR 0007 decision 4 is quoted verbatim
  in the ADR; rewriting it would erase the decision being carried out. The
  backcompat fixtures are captures of published 0.4.0/0.4.3/0.5.5 binaries and
  are regenerated only when a new baseline is cut. Same rule as the "removed in
  0.7.0" prose the row 6 note preserves.
- **Where decision 4 and decision 8 touch, the line falls between the key and
  the value.** The frozen envelope constrains the KEY (`required_action`,
  `next_command`, `suggested_signer_command`, `usage`) and its type; the command
  name INSIDE the value is what decision 4 renames. No schema mentions `uc`
  (`rg -n '\buc\b' schemas/v1/` is empty), no key changed, no type changed.
  `tests/use-cases/compat/backcompat-contract.test.ts` now DECLARES the rename
  on `required_action` alongside the 0.4.1 reason, so it is not silent — that
  path already had a declaration and would otherwise have swallowed it.
- **OWNER-ANSWERED 2026-09-18 — `uc://` and `uc/<prompt>` ARE renamed.**
  Decision 8 freezes the CLI JSON envelope, the 27 schemas, the marker syntax
  and the ledger formats; an MCP resource URI scheme and a prompt name are on
  none of those lists and are squarely inside decision 4's "the MCP server".
  Checked first that `use-cases` is a legal scheme that `new URL` splits
  identically: `use-cases://matrix/status` gives host `matrix`, path `/status`,
  exactly as `uc://` did — `McpResourceUri` mirrors that split. The old scheme
  and the old prompt names are REFUSED, not aliased (`-32002 Unknown resource`,
  `-32602 Unknown prompt`), proved by hand against the Swift binary. The owner
  approved this and the refusal behaviour; it is settled, not a standing
  question. To reverse it: the scheme constant in `McpResourceUri.swift`,
  `McpResourceCatalog`, the four prompt names, the two TypeScript mirrors, then
  regenerate `McpGoldenCorpus`.
- **OWNER-ANSWERED 2026-09-18 — `bin/uc` is DELETED. No alias and no
  tombstone.** A tombstone (a `bin/uc` that execs nothing, prints "the command
  is now `use-cases`" and exits 2) was built first and then removed: the owner
  read decision 4's "no alias" strictly — the file goes. The consequence is
  accepted and is the point: a stale 0.7.0-era `.githooks/pre-commit` in an
  adopter's own repo that calls `uc` now fails with the shell's own
  `command not found: uc`, and the plugin says nothing to them. The cure for
  such a repo is re-running `use-cases init`, which rewrites the hook block.
  `dist/uc.js` and `dist/uc-mcp.js` are NOT affected — the resolver's bundle
  map never named `bin/uc`, and row 10 still owns them.
  Swept after deleting: no live reference to `bin/uc` survives in `bin/`,
  `hooks/`, `tests/`, `docs/` (outside these records), `skills/`, `agents/`,
  `scripts/`, the manifests or the rows. The only mention left in code is
  `session-path.test.ts` asserting the file is ABSENT.
- **The `#bin` binding moved with the behaviour.**
  `plugin.install.uc_on_path_in_session#bin` was rebound through the CLI onto
  `bin/use-cases` (reason `row 8: the hard rename — the session command is
  bin/use-cases`). The row id, the scenario ids and the binding slug are
  unchanged, as decision 4 requires: an id containing "uc" is not a rename
  target. The row gained one scenario,
  `bad_the_old_name_is_gone`, which asserts what is now true — the plugin ships
  no entry point under the old name and `command -v uc` resolves to nothing
  after the session hook exports `bin/`. That scenario is what stops an alias
  being reinstated later, which is why it is worth a row rather than nothing.
- **`SkillText.prefixes` and every skill/agent body had to move together.** The
  CLI-citation extractor is `` /`(?:uc|pnpm cli --)\s+([^`]+?)`/g `` in three
  places (`validateSkillAssets.ts`, `SkillText.swift`, and the two test copies
  in `agents-roster.test.ts` / `p7-skills.test.ts` / `plugin-init-loop-skill.test.ts`).
  Renaming the prefix while bodies still said `` `uc scan` `` would make the
  validator extract NOTHING and the gate pass having asserted nothing. The
  adversarial fixtures in `generate-skills-corpus.mjs` (nbsp, em-space, BOM,
  U+0085, nested backticks, `ucmatrix`) were renamed in step so they still
  exercise the same backtracking edges — `ucmatrix` became `use-casesmatrix`.
- **The scaffolded git hook's shell variable and override moved too**:
  `uc="${UC:-…}"` is now `use_cases="${USE_CASES:-$(command -v use-cases …)}"`.
  `use-cases` is not a legal shell identifier, so the variable had to change
  anyway; `USE_CASES` follows row 6's `USE_CASES_*` convention and stops the
  hook telling a user to set a variable named after the retired command.
  Adopters' already-scaffolded hooks are their files and are not rewritten.
- **Env vars that did NOT move, deliberately.** `UCM_*` are error codes in the
  frozen envelope (decision 8). `UC_BIN` / `UC_MCP_BIN` are the black-box
  harness's seam and `tests/helpers/uc-binary.ts` keeps its name — row 7 left
  the oracle's default to row 10 and that is unchanged. `UC_RUN_KEY_FILE` is an
  env knob, not "the command, the MCP server, skills, agents, hooks or docs".
- **Left to row 10, as row 7 left them**: `dist/uc.js` / `dist/uc-mcp.js`, the
  resolver's Node branch and the bootstrap's `fallback_hint` that names them,
  `.githooks/{pre-commit,pre-push}` (they run `node dist/uc.js`; only their
  human advice strings were renamed), `scripts/bundle.mjs`, and
  `packages/core/test/init/scaffold-sample.test.ts`.
- **The npm `bin` aliases are gone.** `packages/cli/package.json` mapped both
  `uc` and `use-cases`, and `packages/mcp/package.json` both `uc-mcp` and
  `use-cases-mcp`; the short names are removed and both READMEs stopped
  advertising a "long-form alias", which decision 4 abolishes. npm publishing
  itself went at 0.7.0, so nothing consumes these today.
- **`generate-showcase-corpus.mjs` is NOT byte-reproducible.** Re-running it
  changes exactly one substring — a freshly minted ECDSA P-256 WebAuthn
  signature in `webauthn_p256` (P-256 signing is randomised). Nothing else
  moves. The regenerated file was reverted here because the rename does not
  reach it; a future row that must regenerate it should expect that one-line
  churn and not read it as drift.
- **A clean TypeScript rebuild is required before any generator runs.** Every
  generator refuses when `dist/**.js` is older than its `.ts`, and a
  whole-tree rewrite bumps the mtime of files `tsc -b` then declines to rebuild.
  `pnpm clean && rm -f packages/*/*.tsbuildinfo && pnpm build` is what unsticks it.
- **Closed here, from row 5:** `showcase_request_approval`'s
  `suggested_signer_command` is now `["use-cases","approve-run",…]`, and no `uc`
  survives in the four MCP prompt bodies.

## Candidate hardening (contract change — owner's call, after 0.8.0)

- `keyring.schema.json` puts no pattern on `key_id`. Without exact-byte key
  identity, a proof signed under one Unicode spelling could pick up another
  spelling's key; the port now compares exactly, but the schema still allows
  such ids. (Found in 3d2.)

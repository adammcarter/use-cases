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

## Row 10a — the black-box oracle, rewritten in Swift

### Where it lives, and why it depends on nothing

A fourth package, `UseCasesOracle/`, whose `Package.swift` declares ONE target:
a test target with no dependencies at all. That is the structural expression of
"black box". An oracle that linked `UseCasesCore` could shortcut an assertion
through the very code it is meant to hold to account, and one that depended on
the CLI or MCP package would stop compiling the day 10d deletes something. It
also cannot live inside `UseCasesCLI` or `UseCasesMCP`, because it drives BOTH
binaries and neither package depends on the other.

The price of zero dependencies is that `swift test --package-path UseCasesOracle`
does not build the binaries. So the binaries must already be built, and a
missing or unrunnable one FAILS LOUDLY and is never replaced by a fallback —
which is exactly what `harness.test.ts` exists to pin. `TestSupport`'s
`TemporaryDirectory` was copied rather than imported, for the same reason.

- `UC_BIN` unset resolves `UseCasesCLI/.build/{debug,release}/use-cases`;
  `UC_MCP_BIN` unset resolves `UseCasesMCP/.build/{debug,release}/use-cases-mcp`.
- Either variable, set, names the binary verbatim — which is how the same suite
  was pointed at `dist/uc.js` and `dist/uc-mcp.js` (both are executable with a
  `#!/usr/bin/env node` shebang, so no wrapper script is needed).
- `.swiftlint.yml` gained `UseCasesOracle` under `included:` — checked by
  deliberately breaking a line and watching lint fail, because a package absent
  from `included:` lints 0 violations having read nothing. Same silent-green
  class as row 9's `--filter` trap.

### The two helpers

- `Harness/CliBinary.swift` — the Swift shape of `tests/helpers/uc-binary.ts`:
  resolve (command + leading args + `overridden`), `run` (never throws on a
  nonzero exit), `runJson` (throws only on unparseable stdout, naming the
  command and attaching stderr). Both streams go to FILES under a private temp
  directory, never pipes: a `scan` over a large repo outruns a 64KB pipe buffer
  and a reader that is not draining it deadlocks. The process is awaited on an
  `AsyncStream` fed by `terminationHandler` — nothing polls.
- `Harness/McpSession.swift` — the Swift shape of `tests/helpers/mcp-server.ts`:
  an `actor` holding the pending table, stdout chunks arriving on an
  `AsyncStream` fed by the pipe's `readabilityHandler`, newline framing, ids
  matched across interleaved lines, a 15 second ceiling per request implemented
  as a `withThrowingTaskGroup` race against `Task.sleep`. A released session
  terminates its server in `deinit`, which is what the TypeScript's
  `afterAll(() => sessions.forEach(s => s.stop()))` did in one place.
- `Harness/OracleJson.swift` — a small independent JSON reader. The oracle
  cannot borrow `UseCasesCore`'s `JSONValue`: a black-box test that decoded with
  the product's own decoder stops being black-box the moment that decoder is
  wrong.

### Two harness bugs the port had to find, both measured

- **`FileHandle.bytes` starves the cooperative pool.** The first `McpSession`
  read stdout with `handle.bytes.lines`. With six MCP sessions in parallel every
  request timed out at 15s; one test passed. `readabilityHandler` + an
  `AsyncStream<Data>` (the exact shape of `child.stdout.on("data")`) fixed it.
- **Registering the continuation AFTER writing the frame is a real race.** Under
  a loaded full-suite run the server answered while the caller was still hopping
  onto the actor, `consume` found no pending id, dropped the line, and the
  request sat until the ceiling. The frame is now written INSIDE the continuation
  body, after the id is in the table — which is the order `mcp-server.ts` keeps.
  Two runs failed this way before the fix; every run since has passed.

### The faithfulness proof

Both binaries, same suite, same numbers:

| run | result |
|---|---|
| Swift `use-cases` + `use-cases-mcp` (default resolution) | **229 tests in 68 suites passed** (6 skipped), 39.6s |
| `UC_BIN=dist/uc.js UC_MCP_BIN=dist/uc-mcp.js` | **229 tests in 68 suites passed** (6 skipped), 11.7s |

229 is test FUNCTIONS, which is how the runner counts them, and it INCLUDES the
6 disabled todos (223 ran, 6 skipped) — so it compares like for like with the
TS column below, which includes its 6 `test.todo`. 10 of the 229 are
parameterised and expand to 30 cases, so 249 cases are executed.

Equal counts on both sides is the check that matters: a Swift-229 / Node-fewer
pair would mean some tests silently no-opped against one binary. Both sides were
run three times consecutively at this count (Swift 50.7s / 41.1s / 39.6s, Node
11.7s / 12.2s / 12.3s) — the parallel race described above was load-dependent,
so a single green run is not evidence of a stable one.

**What the 229 actually exercises.** Not all of them talk to the binary under
test, and the honest number is worth stating in a subrow about not overstating
an oracle. Running the whole suite against a binary that does nothing
(`UC_BIN=<a script that exits 0>`, `UC_MCP_BIN=/bin/cat`) leaves **18 test
functions (32 test cases) still passing**: the `plugin-install-claude` manifest
checks, most of `agents-roster`'s body assertions, two of the
`plugin-init-loop-skill` pattern checks, and all six `HarnessTests` (which drive
shell stubs, or the built Swift CLI by construction). Fifteen of those 18 read shipped
repository artifacts; the other three are the `HarnessTests` default-resolution
cases, which drive the built Swift CLI by construction. Either way they are
constant across the two binaries by design. The
cross-check above is therefore a claim about **211 test functions**, which is
still the whole of the product surface these files cover.

### The oracle can fail

A suite that cannot go red proves nothing, and two of the three helper bugs
found here were of the kind that turns a test into a no-op. So both seams were
measured against a lying binary:

| liar | result |
|---|---|
| `UC_BIN=<script: exit 0>` over four CLI suites | 14 tests, **19 issues**, all red |
| `UC_MCP_BIN=/bin/cat` over all 9 MCP suites | 26 tests, **74 issues**, all red |

`/bin/cat` is the sharpest MCP liar available: it echoes each request back, so
the reply carries the right `id` and the session resolves normally — only the
`result` is missing. A test that passes against it is not reading the server.

The first `/bin/cat` run found exactly two such tests, both of them assertions
about an ABSENCE (`prove` is not in the tool list; a read mutates nothing), which
an empty answer satisfies. Each now carries a positive guard for the surface it
is an absence from — the tool list has to have been listed, each resource read
has to have returned content — and both go red against `/bin/cat`. A third,
`a results ledger attested on another machine reads unattested here`, had the
same shape for a different reason: it re-serialises the record with sorted keys
before changing the machine key, so a byte-sensitive attestation would fail for
the wrong reason. It now reads the rewritten ledger under the ORIGINAL key first
and expects `VERIFIED_LOCAL`, which passes — the product hashes the parsed
record, not the raw line — so the second read isolates the key, as intended.

Per file, TS tests → Swift `@Test` functions (the TS counts include `test.todo`):

| TypeScript file | TS | Swift | Swift file(s) |
|---|---|---|---|
| agents-roster | 10 | 10 | `AgentsRosterTests` (3 suites) |
| capsule-demos | 14 | 14 | `CapsuleDemosTests` 7 + `CapsuleCommandSafetyTests` 7 |
| capsule-runner | 3 | 3 | `CapsuleRunnerTests` |
| diagnostics-contracts | 11 | 11 | `DiagnosticsContractsTests` (4 suites) |
| evidence-core | 3 | 3 | `EvidenceCoreTests` |
| evidence-ledger | 9 | 9 | `EvidenceLedgerTests` (4 suites) |
| harness | 5 | **6** | `HarnessTests` — one ADDED, see below |
| lifecycle-bindings | 15 | 15 | `LifecycleBindingsTests` (3 suites) |
| lifecycle-signals | 50 | 50 | 9 files, 12 suites |
| matrix-core | 7 | 7 | `MatrixCoreTests` (2 suites) |
| matrix-product-inventory | 9 | 9 | `MatrixProductInventoryTests` (3 suites) |
| matrix-product | 5 | 5 | `MatrixProductTests` (2 suites) |
| mcp-resources | 8 | 8 | `McpResourcesTests` (3 suites) |
| mcp-surface | 12 | 12 | `McpSurfaceTests` (5 suites) |
| mcp-wrapper | 6 | 6 | `McpWrapperTests` |
| planning-cards | 14 | 14 | `PlanningCardsTests` (5 suites) |
| plugin-init-loop-skill | 4 | 4 | `PluginInitLoopSkillTests` |
| plugin-install-claude | 5 | 5 | `PluginInstallClaudeTests` |
| security-redaction | 4 | 4 | `SecurityRedactionTests` |
| showcase-flow | 20 | 20 | `ShowcaseFlowTests` 9 + `ShowcaseFailureDecisionsTests` 7 + `ShowcaseApprovalBoundaryTests` 4 |
| skills-assets-validation | 6 | 6 | `SkillsAssetsValidationTests` (2 suites) |
| skills-assets | 8 | 8 | `SkillsAssetsTests` (2 suites) |
| **total** | **228** | **229** | |

Nothing was dropped. The differences, all deliberate:

- **`harness.test.ts` could not be transcribed, and gained a test.** It asserts
  the TS seam's NODE default (`leadingArgs[0]` ends `packages/cli/dist/index.js`)
  and mutates `process.env.UC_BIN` around each case. Swift Testing runs a suite
  in one process in parallel, where `setenv` is unsafe and visible to every other
  test, so the override is a PARAMETER (`CliBinary.resolved(override:)`) and the
  default under test is the Swift build. The five properties are all carried
  (default resolves to the build under test; `UC_BIN` is honoured; a nonzero exit
  is returned not thrown; unparseable stdout fails naming the command; `run`
  hands back raw stdout). The sixth is NEW and is the reason the file exists: a
  `UC_BIN` naming a missing or non-executable path is REFUSED, never silently
  replaced by the default. In TypeScript that mistake was unrepresentable —
  `spawnSync` simply failed; in Swift the seam resolves a path itself and could
  fall back, and nothing else would notice.
- **Two files never touch a binary, so their dual-run pass proves nothing about
  either build.** `plugin-install-claude` reads only the shipped manifests, and
  `HarnessTests`' default-resolution case always runs the Swift build whichever
  binary the run is pointed at. Both are still worth having; neither is evidence
  of parity.
- **Parameterisation, per house style.** Nine `@Test` functions carry
  `arguments:` where the TypeScript looped inside one test (e.g. the roster's
  three agent bodies, the redaction forbidden-pattern list, the three showcase
  actors). The function count is unchanged; the case count is higher.

### The six todos

Swift Testing has no `todo`, so each is `@Test(.disabled("<the same reason>"))`
with a body that records an issue if it is ever reached. They are listed in the
run, reported as skipped with their reason, and cannot go green by accident:

- `plugin-install-claude`: `edge_live_session` (a host observation).
- `skills-assets`: `bad_misdirected` (the row claims behaviour the tool lacks).
- `matrix-product-inventory`: `golden_cli`'s usage/scenario half (`matrix list`
  projects neither).
- `showcase-flow`: all three `revision_epoch_staleness` scenarios (no CLI
  command appends an `epoch_started` event).

### Found while porting

- **`#expect(!(x?.y ?? []).isEmpty)` reports a FALSE FAILURE.** The Swift
  Testing macro expands a negated property access over an optional chain into
  `__checkPropertyAccess` on the OPTIONAL, and the `?? []` is lost: the check
  fails while the array is non-empty. Hit three times, on assertions that were
  correct. It fails LOUD (never a false pass), but the cure is to bind the value
  to a `let` first, and every site in the oracle now does.
- **`FileManager.enumerator` answers `/private/var/…` while a
  `TemporaryDirectory`'s own `path` is `/var/…`**, so trimming the prefix off
  enumerated paths silently yielded ABSOLUTE paths. Two "the run directory holds
  only the ledger" assertions caught it; three earlier uses had masked it by
  comparing two lists produced the same way. Both sides are now resolved before
  the trim, and `TemporaryDirectory.realPath` (realpath(3), which is what Node's
  `realpathSync` answers and what a product process reports as its cwd) is
  separate from `resolvingSymlinksInPath()`, which strips `/private`.
- **The oracle needed an ed25519 keypair without a dependency.** `showcase-flow`
  mints one with `node:crypto`. Swift uses CryptoKit — a system framework, not a
  package dependency — wrapped in the two fixed DER envelopes RFC 8410 defines
  for this curve (16-byte PKCS#8 prefix, 12-byte SPKI prefix, raw key appended).
  `approve-run` accepts the PEM and the signed token verifies, so the key stays
  INDEPENDENT of the binary under test, which is the property that matters.
- **The `skills-assets` pair share one `ShippedPluginCopy` helper.** Each
  TypeScript file carried its own byte-identical `makePluginCopy`; a Swift test
  target is one module with one namespace. The helper builds a layout and
  asserts nothing, so an edit to it cannot restate what a row promises.
- **`impact --repo .` against this repository takes ~47s**, which is most of the
  oracle's wall clock. It is what `agents-roster.test.ts` does too.

### Left for 10b/10c/10d

Nothing here was rebound and no TypeScript was deleted: the 22 oracle files, the
markers in them, every row's verifier and the vitest suite are all untouched, so
`pnpm test` and `use-cases verify --all` still measure exactly what they did
before. `.swiftlint.yml` is the only config that needed a line (the package is
outside the existing `included:` roots); `.gitignore` needed none, because its
bare `.build/` matches at any depth — `git status --untracked-files=all
UseCasesOracle` lists no build or `.swiftpm` path, so the untracked directory
can be added whole. `UseCasesOracle` is not in `.github/workflows/ci.yml`, which runs on
ubuntu and builds no Swift at all — wiring the Swift suites into CI is a
separate job that 10d will have to face when `pnpm -s test` stops existing.

### Owner question

`.github/workflows/ci.yml` runs on ubuntu and builds no Swift, so today the only
gate in CI is the vitest suite that 10d deletes. Should the Swift suites (Core,
CLI, MCP and `UseCasesOracle`) be wired into CI as part of 10b — which needs a
macOS runner, since the oracle drives real binaries and the bootstrap suites are
already Apple-Silicon-gated — or does 10d land with `pnpm -s test` gone and no
Swift gate until a later row? 10d cannot safely remove the TypeScript until this
is answered.

## Row 10b — the surviving script tests, and the Swift CI gate

### The file set is ten, measured

Row 9 named `tests/plugin/*`, `tests/conformance/bootstrap/session-start.test.ts`
and `tests/skills/init-skill.test.ts` as SURVIVES-ROW-10. Measured here by
reading every import in `tests/**` (`from "…packages/…"`, `dist/`, `node_modules`,
`pnpm`): **ten files** import no TypeScript and test bash, YAML, markdown and
JSON only —

  `tests/plugin/{bootstrap-cache,bootstrap-failures,bootstrap-first-run,
  host-manifests,opencode-plugin,release-workflow,runtime-resolver,
  session-path}.test.ts`, `tests/conformance/bootstrap/session-start.test.ts`,
  `tests/skills/init-skill.test.ts`.

Two files in `tests/plugin/` are NOT in the set, each for its own reason:
`claude-install.test.ts` imports `CANONICAL_SKILLS` from `packages/core` and dies
with it (it is on row 9's left-undone list), and `bundle.test.ts` is on row 9's
"dies with the TypeScript, deliberately" list.

### Where they went, and why

`UseCasesOracle`, as new files under `Tests/OracleTests/Plugin/`. The subjects are
processes and shipped files — `bin/use-cases-bootstrap`, `bin/use-cases`,
`hooks/session-start`, the four host manifests, `.github/workflows/release.yml`,
`opencode/plugin.js`, `skills/init/SKILL.md` — which is exactly what the oracle
package exists to drive: it links NOTHING, so it can survive 10d, and it already
owns `OracleProcess`, `TemporaryDirectory` and the `UC_BIN` seam. Putting them in
`UseCasesCore`'s test target would have linked the product into tests that must
not see it; putting them in `UseCasesCLI` or `UseCasesMCP` would have tied files
about the PLUGIN to one of the two binaries.

Per file, TS tests → Swift `@Test` functions:

| TypeScript file | TS | Swift | Swift file |
|---|---|---|---|
| plugin/bootstrap-first-run | 7 | 7 | `BootstrapFirstRunTests` |
| plugin/bootstrap-cache | 4 | 4 | `BootstrapCacheTests` |
| plugin/bootstrap-failures | 7 | 7 | `BootstrapFailuresTests` |
| plugin/release-workflow | 8 | 8 | `ReleaseWorkflowTests` |
| plugin/host-manifests | 5 | 5 | `HostManifestsTests` (2 disabled) |
| plugin/opencode-plugin | 4 | 4 | `OpencodePluginTests` (1 disabled) |
| plugin/session-path | 7 | 7 | `SessionPathTests` |
| plugin/runtime-resolver | 8 | **4** | `RuntimeResolverTests` — see below |
| conformance/bootstrap/session-start | 6 | 6 | `SessionStartBootstrapTests` |
| skills/init-skill | 2 | 2 | `InitSkillTests` |
| **total** | **58** | **54** | |

The four differences, all deliberate:

- **`runtime-resolver`'s second describe is not carried.** Its four tests pin
  `plugin.runtime.pre_swift_versions_run_the_committed_bundle` — the resolver's
  Node branch — which row 10 already schedules for RETIREMENT rather than
  rebinding, and which 10d deletes with `dist/`. Porting it would be writing
  Swift for behaviour that is about to stop existing. One test of the FIRST
  describe shares that fate and is carried anyway, flagged in the file:
  `a version that is not a semantic version is refused` pins
  `bin/use-cases-runtime`'s version parsing, and row 10 says the resolver can be
  folded away entirely once the Node branch goes.
- **The three `test.skip("live: …")` cases are `@Test(.disabled(…))`** with a body
  that records an issue if reached — 10a's shape, so they are listed, skipped
  with their reason, and cannot go green by accident.
- **Four TypeScript in-test loops became `arguments:`** (the two unsupported
  machines, the two host shapes of the session bootstrap, the two `bin/` entry
  points, and the YAML reader's refused constructs). Function count unchanged,
  case count higher.
- **One fixture moved.** `opencode-plugin`'s "a missing bootstrap" case points at
  `tests/fixtures/workspaces/minimal-valid`, a tree 10d deletes; the Swift test
  uses an empty temporary directory, which proves the same thing and leaves 10d
  nothing to trip over.

Three new Swift files have no TypeScript counterpart: `Harness/ReleaseStandIn.swift`
(below), `Harness/OracleYaml.swift` + its 3 tests, and `Plugin/CiWorkflowTests.swift`
(7 tests, the new row). Oracle totals: **229 → 293 test functions in 80 suites passed
(9 skipped)** — the 6 todos 10a carried plus the 3 `live:` cases above — against
both the Swift binaries and `dist/uc.js` / `dist/uc-mcp.js`, at the same count on
each side.

### Apple-Silicon gating, in Swift

`describe.skipIf(!canRunBootstrap)` has no home in the house style (no `@Suite`),
so the condition is a trait on each test: `@Test(.enabled(if: ReleaseStandIn.canRunBootstrap))`.
Twenty-three of the fifty-four migrated tests carry it — all of
`Bootstrap{FirstRun,Cache,Failures}Tests`, two of `ReleaseWorkflowTests` and three
of `RuntimeResolverTests`, which is the same set the TypeScript gates.

`canRunBootstrap` reads `uname(2)` at runtime, exactly as `platform()`/`arch()` did.
Proved BOTH ways, because a trait that is always false skips silently and exits 0:

- as it stands (darwin/arm64) the five gated suites run 30 tests, none skipped;
- with the flag forced to `false`, the same five report **23 skipped and 7 run**
  (the six text-only `ReleaseWorkflowTests` and the one version-refusal case).

The first measurement caught a real bug in this file: `utsname`'s fields are C
char arrays, and reading one through an `Any` parameter boxes a copy, so the
first version answered `""` and **every download test skipped while the suite
reported 7 tests passed**. `hostPlatform()` now THROWS off Apple Silicon rather
than answering a slug nothing publishes, so a future download test that forgets
the trait fails loudly instead of passing against the wrong asset.

### The stand-in release needs no server

`tests/helpers/release-stand-in.ts` never ran an HTTP server — it publishes a
release into a temp directory and hands back a `file://` URL, and the bootstrap's
`curl` reads that with the same exit codes it gives for a missing remote asset
(37 → "absent"). `Harness/ReleaseStandIn.swift` is the same shape, with three
deliberate differences:

- **No `scratch()` / `cleanupScratch()`.** Every temporary tree is a
  `TemporaryDirectory` owned by the value that needs it; a module-level list
  emptied in an `afterEach` is shared mutable state across tests that now run in
  parallel in one process.
- **The archive's SHA256 is computed with CryptoKit**, not by shelling out to
  `shasum`. The oracle computing the digest itself is the stronger side of a
  black box.
- **`baseUrl` has its trailing slash trimmed.** `URL(fileURLWithPath:).absoluteString`
  ends a directory with `/` and Node's `pathToFileURL` does not; the bootstrap
  strips one either way, but the tests compare the URL it echoes back.

`OracleProcess.run` gained `inheritEnvironment:` for this. The bootstrap suite's
whole hermeticity rests on every `USE_CASES_*` and `XDG_CACHE_HOME` being ABSENT,
and a merge over the test process's environment cannot express an absence.

### A YAML reader the oracle owns

The TypeScript parsed workflows with the `yaml` npm package. A zero-dependency
oracle cannot, and must not borrow `UseCasesCore`'s parser — a black-box test that
read a workflow with the product's own reader stops being black-box the moment
that reader is wrong. `Harness/OracleYaml.swift` is the independent replacement,
the same argument `OracleJson` already carries: block mappings, block sequences,
literal/folded scalars and comments, and a THROW on anything else (flow
collections, anchors, aliases, tags). Refusing rather than half-reading is the
point — a reader that silently returned an empty mapping would make every "this
key is absent" assertion pass having read nothing, which is the `/bin/cat` class
of vacuity 10a found. Its three tests pin that, and the three workflow mutations
below prove it bites in the positive direction.

One simplification: `on:` is a key like any other here, so the TypeScript's
`workflow.on ?? workflow["true"]` dance for YAML 1.1's boolean `on` disappears.

### Two harness faults found while porting

- **`OracleJson.encoded` escaped forward slashes.** `JSONSerialization` writes
  `"a\/b"` where `JSON.stringify` writes `"a/b"`, so every `encoded.contains("<a
  path>")` carried over from the TypeScript was false — and the ones asserting an
  ABSENCE passed having read nothing. `PluginInstallClaudeTests`' "no host
  manifest names the committed bundle" was one of them. Fixed with
  `.withoutEscapingSlashes` and measured: pointing the Claude manifest at
  `dist/uc-mcp.js` now fails that assertion, and did not before.
- **`#expect(!(a?.b ?? c).d)` reports a false failure**, exactly as 10a recorded.
  Hit once (a skill body's `hasPrefix("---")`); the value is bound to a `let`
  first.

### The CI gate

`.github/workflows/swift.yml`, new, additive: `ci.yml` and `use-cases.yml` are
untouched, so 10d removes `ci.yml` whole rather than editing it. One job on
**`macos-15`** — GitHub's Apple Silicon image, and the same label `release.yml`
publishes from, so the gate runs on the machine the release is built on. It
builds the three products, tests all four packages, points the oracle at the
freshly built binaries through `UC_BIN`/`UC_MCP_BIN` (checking the executable bit
first, because a harness that cannot find its binary must fail rather than fall
back), runs `swiftformat --lint` and `swiftlint lint --strict`, and ends by
gating the matrix with the binary it just built: `verify --repo . --all` then
`scan --repo . --gate`.

Three guards exist because of faults this ladder has already measured:

- **the runner's architecture is asserted, not taken from the label.** On a
  non-arm64 runner every bootstrap suite skips and the job passes having proved
  nothing about `release.distribution.*`, so `uname -m` is checked and the job
  refuses.
- **each lint step proves it READ something.** A package missing from
  `.swiftlint.yml`'s `included:` lints zero files and reports zero violations
  (10a). Both steps grep their own output for a non-zero file count.
- **the gate runs the built binary, not `bin/use-cases`.** The wrapper resolves
  to the committed Node bundle at 0.7.0; gating through it would prove the wrong
  product.

`--policy-mode feature` is passed explicitly rather than inherited, because the
mode is what sets the bar. Measured with the built binary: default and
`--policy-mode feature` both exit 0, `--policy-mode release` exits 1 (nothing is
FRESH — there are no signed proofs, and minting them is `use-cases.yml`'s prove
job with a key this workflow never sees). `--public-key` is deliberately NOT
passed: with it, 41 rows read SUSPECT against stale signed proofs, which changes
the report without changing the gate. `actions/checkout@v4`'s default
`fetch-depth: 1` is also deliberate — `use-cases.yml` needs `0` because it passes
`--base-ref` for the append-only check, and this gate passes none.

**The gate cannot be pure Swift yet, and that is an ordering fact, not a choice.**
All 93 row verifiers are still `pnpm -s vitest run <file>`, and one of them
(`tests/cli/recover.test.ts`) runs a REAL pytest verifier. Measured: with `pnpm`
off PATH a verifier command exits 127 (`command not found`) and `verify` records
`status: fail` with `exit_code: 1`, and on
a pristine `git archive` checkout `scan --gate` exits 1 (the local-✓ ledger
`.use-cases/verification-results.jsonl` is gitignored, so CI has to produce it by
running `verify` itself). So the workflow carries `setup-node`, `pnpm install`,
`pnpm -s build` and a `pip install pytest` ahead of the gate. Everything but
`setup-node` goes with 10c, which re-points the verifiers onto `swift test`;
`setup-node` stays, because `OpencodePluginTests` runs `opencode/plugin.js` and
proving what JavaScript registers means running it.

**What is unproven until the workflow first runs.** It has never fired and
nothing here can fire it. Validated locally: the YAML parses (through the `yaml`
package and through `OracleYaml`), and every step's commands were run by hand on
this machine — the arm64 guard, all four `swift test` invocations with `UC_BIN`
set the way the step sets it, both lint gates including their file-count greps,
`pnpm install --frozen-lockfile`, `pnpm -s build`, `verify --repo . --all` (89/89,
2m46s) and `scan --repo . --gate` (exit 0). `actionlint` is not installed on this
machine and was not run. Unproven: that `macos-15` resolves to an arm64 image
(the guard is what turns that from a silent skip into a failure), that
`brew install swiftformat swiftlint` succeeds on the runner and installs versions
whose defaults agree with 0.62.1 / 0.65.1, that `python3 -m pip install --user
pytest` works on the image, that the runner's Node and the frozen lockfile
install cleanly, and the wall-clock of a full `verify --all` there.

### The row, and the first Swift marker

New row `ci.gate.swift_packages_are_built_tested_and_gated` in a new feature file
`use-cases/ci/gate.yml` (feature `ci.gate`), five scenarios, vended with
`matrix upsert`. `matrix upsert` REFUSES to create a file and refuses to mutate an
incomplete matrix, so a new feature file cannot be born from the CLI alone: the
file was seeded with the row and then upserted over, which is a no-op hash
(`before_hash == after_hash`) and leaves the committed bytes the CLI's own
rendering. Worth knowing before the next new feature file.

Its verifier is the first `swift test` verifier in the matrix:
`swift test --package-path UseCasesOracle --filter CiWorkflowTests`, run and read
(7 tests, 1 suite) rather than trusted — row 9's `--filter` trap.

Bound with `bind --mode explicit` onto `CiWorkflowTests.swift`, the first
use-case marker in a Swift file. Two things learned:

- **the marker cannot sit between a doc comment and its declaration** — swiftlint
  reports `orphaned_doc_comment`. The span therefore starts at line 1, above the
  imports: the whole file is the row's proof anyway.
- **swiftformat wants a blank line before the closing marker**, and inserting it
  changes the span's hash. Format first, then `verify`; doing it the other way
  round leaves the row SUSPECT for no reason.

Nothing else was rebound: the ten migrated files' rows still point at the
TypeScript, exactly as 10a left the oracle's twenty-two, and 10c moves them.

### Owner questions

- **`package.json` and OpenCode.** `opencode-plugin.test.ts`'s first test asserts
  `package.json` exports `./opencode/plugin.js` and `"type": "module"` — which is
  how OpenCode resolves the plugin from a git install. It is carried as it stands,
  because it is true today, but 10d deleting `package.json` either breaks the
  OpenCode install, or keeps a minimal `package.json` for exactly these two keys,
  or retires `plugin.install.opencode_from_git`. That is a decision, not a
  migration detail.
- **`verify --all` in CI.** The temporary Node/pnpm/pytest prelude is the honest
  way to have the gate actually gate today. The alternatives were: land the Swift
  gate without `verify`/`scan` until 10c re-points the verifiers, or give the
  gate `continue-on-error` (rejected outright — a gate that cannot fail is not
  one). If the prelude is unwanted, the verify and scan steps belong to 10c.
- **After 10d, `SessionPathTests`' first test downloads.** `bin/use-cases` at a
  Swift-era version goes to the bootstrap, so "runs the resolved runtime from any
  working directory" would try to fetch a real release in CI. 10c or 10d has to
  point it at a stand-in release or retire it.
- **Two migrated tests READ `ci.yml` and throw the day it is deleted.**
  `ReleaseWorkflowTests.the release pipeline is its own workflow and leaves the
  existing gates alone` asserts `ci.yml` still carries `pnpm -s test` and
  `pnpm -s build`; `CiWorkflowTests.the Swift gate is its own workflow and leaves
  the existing gates alone` asserts `ci.yml` names no `swift`. Both are true and
  worth having until 10d; both are a file read that fails once `ci.yml` is gone.
  10d owns them — the second one's purpose (the Swift gate publishes nothing)
  survives without the `ci.yml` half.

## Row 10c — the markers and the verifiers move off the TypeScript

### The measured starting point

`scan --json` over 118 rows, 2026-09-18, before any change: **123 bindings**, of
which 32 lived in `packages/**`, 67 in `tests/blackbox/**`, 19 elsewhere under
`tests/**`, 1 in `scripts/bundle.mjs`, 3 in shell/JS that survives
(`bin/use-cases`, `hooks/session-start`, `opencode/plugin.js`) and 1 already in
Swift (10b's `CiWorkflowTests`). **94 verifiers**, 93 of them
`pnpm -s vitest run <file>`.

Row 9's framing — "for the 24 rows bound into BOTH `packages/` and
`tests/blackbox/`, the rebind is dropping the `packages/` span and keeping the
black-box one" — was written before 10a. It is stale: the black-box span is no
longer a safe harbour, because `tests/blackbox/*.test.ts` dies with the
TypeScript too. 10b's own note is the one that holds ("the ten migrated files'
rows still point at the TypeScript, exactly as 10a left the oracle's twenty-two,
and 10c moves them"), so BOTH spans moved.

**112 of the 123 bindings are now in Swift** (98 Swift + 3 surviving shell/JS +
11 left in TypeScript, listed below). Of the 94 verifiers, **87 now run `swift test`** (78
`UseCasesOracle`, 7 `UseCasesCore`, 2 `UseCasesCLI`) — 86 of them moved here, the
87th being 10b's `ci.gate` row. Four active rows and the three `removed`
`hosts.profiles.*` rows still run vitest. Verifier INPUTS moved with the
commands: the only `packages/`, `scripts/` or `tests/` paths left in any
verifier's `inputs` belong to those seven rows.

### `swift test --filter` also matches the SOURCE FILE NAME

New, measured here, and it changes how row 9's trap reads. `--filter` is an
unanchored ICU regex matched against the suite name, the test name **and the
file the test is declared in**:

- `--filter ShowcaseFlowTests` — a filename with no struct of that name — runs
  **9 tests in 3 suites**, every suite in `ShowcaseFlowTests.swift`.
- `--filter MatrixCoreValidateTests` — a struct that is NOT its file's name —
  runs **2 tests in 1 suite**, and its sibling `MatrixCoreMutateTests` does not.
- `--filter ZzzNoSuchThing` still prints `warning: No matching test cases were
  run` and **exits 0**. The trap is unchanged.

So seven selectors here (`CapsuleCommandSafetyTests`,
`LifecycleVerifyPreservesTests`, `LifecycleVerifyPreviewTests`,
`MatrixProductInventoryTests`, `SkillsAssetsValidationTests`,
`ShowcaseFailureDecisionsTests`, `WorkspaceScaffoldTests`) name a struct that is
also its file's basename and therefore select that file's other suites as well.
That is a superset, never a subset — the row's own tests always run — but it
means those rows go red for a neighbour's failure. Deliberate and recorded
rather than worked around: splitting the files would churn 10a/10b's layout.

Every selector written was run exactly as written and its count read. 83 distinct
(package, filter) pairs, **all non-zero, none warning**. Counts: 1–9 tests, most
2–5. The full table is in the row 10c report.

### The swift-testing test ID has backticks in it

`swift test list` prints
``OracleTests.LifecycleVariantFanoutTests/`a dry run previews …`()``. A
function-level filter written the obvious way —
`LifecycleVariantFanoutTests/a dry run` — matches NOTHING, because the backtick
sits between the `/` and the name. Measured both ways.

### `{variant}` forced a test rename

`lifecycle.signals.variant_fanout` declares four variants, and `verify` fans a
variant row out by substituting `{variant}` into the command. A command with no
token is not "run once" — `VerifyRun` records `familyTokenMissing` for the whole
family, which is a spec error that spawns nothing (the oracle's own
`a family with no variant token is a spec error and spawns nothing` pins it). So
the token had to survive the port, and the Swift test names carried no variant
key to match on. The four tests were renamed to end `(variant: spawn|verdict|
names|dry)` and the command is
`--filter "LifecycleVariantFanoutTests.*variant: {variant}"`. Measured: one test
per variant, and `verify --row lifecycle.signals.variant_fanout` produces four
`::<key>` records, all `pass`. The fifth test in that suite (the no-token spec
error) is matched by no variant and runs only under the full suite — exactly as
the TypeScript's `-t "variant_fanout {variant}"` left it.

### Two `--filter` flags, not one alternation

`signing.tier.validate_ledger_holds_the_append_only_line` needs two suites. The
command array is eight elements ending
`…,"--filter","EvidenceLedgerTests","--filter","LedgerChainRulesTests"` — 9 tests
in 2 suites. A single element `"EvidenceLedgerTests --filter LedgerChainRulesTests"`
would be one argv and would match nothing; the written YAML was read back, not
just the measured count.

### `verify --all` never runs an UNBOUND row's verifier

Measured: `verify --row signing.tier.keygen_keeps_the_private_key_out_of_the_tree`
answers `no bound behaviours to verify`, `ok: true`, zero results. The same is
true of `lifecycle: removed` rows. So:

- the five `signing.tier.*` rows now carry correct, hand-measured `swift test`
  verifiers (`SigningKeyGenerationTests` 4, `VerifyProveTests` 3,
  `EvidenceLedgerTests`+`LedgerChainRulesTests` 9, `MarkerCommandsGoldenCorpusTests`
  4, `ShowcaseCommandsGoldenCorpusTests` 2) — but **nothing runs them**, because
  the rows are still UNBOUND. Row 9 said they "need real carriers or an explicit
  owner decision"; the carriers exist and are named, and binding them is the
  decision that is still open.
- the three `hosts.profiles.*` rows are `removed` and were left alone. Two of
  them already name `tests/conformance/bootstrap/agent-hook-installer.test.ts`,
  **a file that does not exist** — pre-existing rot, harmless only because the
  rows are never verified.

### The four rows that cannot leave vitest, and why

None has a Swift carrier, and each is a deletion decision rather than a
migration one:

| row | verifier | why there is no Swift carrier |
|---|---|---|
| `diagnostics.contracts.missing_build_hint` | `tests/conformance/cli/cli-ergonomics.test.ts` | the hint exists only because `coreLoader.ts` `await import`s `core/dist/index.js` and translates `ERR_MODULE_NOT_FOUND`. SwiftPM links `UseCasesCore` statically; the behaviour CANNOT exist. Retire it. |
| `plugin.bundle.runs_from_clean_clone` | `tests/plugin/bundle.test.ts` | row 9's "dies with the TypeScript, deliberately". |
| `plugin.runtime.pre_swift_versions_run_the_committed_bundle` | `tests/plugin/runtime-resolver.test.ts` | row 10 already schedules it for RETIREMENT with `dist/`. |
| `skills.assets.demo_gates` | `tests/skills/p7-skills.test.ts` | it reads the LIVE `skills/showcase/SKILL.md` body. `SkillsGoldenCorpus` pins a FROZEN snapshot, so nothing in Swift fails when a real skill body changes. A genuine gap, not an artefact. |

Their bindings stayed where they are, deliberately: unbinding now would hand 10d
a quieter tree, and a marker in a file 10d deletes fails LOUDLY, which is the
correct coupling. Same reasoning for the other seven TypeScript bindings left
behind, all of them duplicates of a span the row now also has in Swift:
`tests/agents/canonical-agents.test.ts` (×2), `tests/cli/known-commands-parity.test.ts`,
`tests/plugin/claude-install.test.ts`, `tests/skills/loop-skill.test.ts`,
`tests/skills/p7-skills.test.ts` (the `host_declaration` one) and
`scripts/bundle.mjs`.

### `tests/cli/recover.test.ts`, answered

`signing.tier.recover_never_fakes_green` now runs
`swift test --package-path UseCasesCLI --filter MarkerCommandsGoldenCorpusTests`
(4 tests), which is row 9's named carrier for the `recoverVariants` half. The
other half — `recover` driving a REAL `pytest` against `examples/python-pytest`
through a `pnpm pack` → `npm install` harness — has no Swift carrier and its
harness dies with the TypeScript regardless. **No Swift test runs a real
verifier toolchain**, which is row 9's finding restated and still open.
Consequence: `pip install pytest` left `.github/workflows/swift.yml`. Measured
before removing it — `swift test --package-path UseCasesOracle --filter
LifecycleRunClassTests`, the only suite that feeds a `python.pytest` preset into
a real `verify`, passes all 5 tests with pytest off PATH, because it asserts the
derived `run_class`, not the run's verdict.

### The workflow prelude: `setup-node` and pnpm stay, pytest goes

`setup-node` is permanent (`OpencodePluginTests` runs `opencode/plugin.js`).
`corepack pnpm install --frozen-lockfile` and `corepack pnpm -s build` stay
because the four rows above still need vitest and the built TypeScript for
`verify --all` to pass. `CiWorkflowTests` asserts nothing about the prelude —
only that the final gate step uses neither `node ` nor `bin/use-cases ` — and it
still passes 7/7 after the edit.

### Markers in Swift, three placement rules learned

- **Above the doc comment, never between it and the declaration** (10b's
  `orphaned_doc_comment`). Every span therefore starts at the first `///` line.
- **swiftformat wants a blank line before the closing marker**
  (`blankLinesBetweenScopes` fires on the `//: @use-case:end` line when a
  declaration follows). Format the whole tree AFTER all the rebinds and BEFORE
  `verify`, or every reformatted span is SUSPECT for no reason.
- **Rebind bottom-up within a file.** The marker pair adds two lines, so any
  span below the one just written shifts. Twenty-one files carry more than one
  row.

### `plugin.init.*` span asymmetry, disclosed

`WorkspaceScaffoldTests` carries two rows and two markers cannot overlap, so
`wires_git_hooks` took the corpus test (`a workspace is scaffolded as the
TypeScript scaffolded it`) and `records_decision_in_agents_md` took the
dated-clock test. The VERIFIER is `--filter WorkspaceScaffoldTests` for both, so
the proof is identical; only `impact`'s file→row mapping is narrower for
`records_decision_in_agents_md`. Forced by the file's shape, not chosen.

### `source_refs` were NOT repointed — and the mapping 10d needs is here

Out of scope as briefed (10c is markers, verifiers, the workflow and
`recover.test.ts`), and measured so the next pass starts from a number:
**79 rows still name a `packages/**` path in `source_refs`, 117 references in
all.** They are documentation pointers, not proof, but every one of them rots at
10d.

The `packages/` → Swift source mapping was established here while moving the
white-box markers, and it is the same mapping that pass needs. Recorded so it is
not searched for twice (each line is where the BEHAVIOUR went, not a file
rename):

| TypeScript | Swift |
|---|---|
| `packages/cli/src/builtins.ts` (`runHelp`, `renderHelpText`) | `UseCasesCLI/…/Help/HelpPresenter.swift` (`present`, `text`) |
| `packages/cli/src/coreLoader.ts` | **nothing** — SwiftPM links Core statically |
| `packages/cli/src/trustRender.ts` (`renderImpact`) | `UseCasesCLI/…/Rendering/TrustRenderer+Impact.swift` (`impactLines`, `touchedLines`, `brokenLines`) |
| `packages/core/src/durableWrite.ts` | `UseCasesCore/…/Evidence/DurableWrite.swift` |
| `packages/core/src/evidence/appendEvidenceEvent.ts` | `UseCasesCore/…/Evidence/EvidenceAppender.swift` (+ `EvidenceEventRecord`) |
| `packages/core/src/evidence/assurance.ts` | `UseCasesCore/…/Evidence/EvidenceAssurance.swift` (`derive`, `evaluateFreshness`) |
| `packages/core/src/evidence/jsonlLedger.ts` | `UseCasesCore/…/Evidence/EvidenceLedgerReader.swift` (`parseLedger`, `LedgerReading`) |
| `packages/core/src/evidence/linkEvidence.ts` | `UseCasesCore/…/Evidence/EvidenceMatrixLinker.swift` |
| `packages/core/src/evidence/performedRuns.ts` | `UseCasesCore/…/Evidence/PerformedRuns.swift` |
| `packages/core/src/init/scaffold.ts` | `UseCasesCore/…/Initialization/ScaffoldFiles.swift` (`ensureGitignoreEntries`, `ensureAgentsMarkdownDecision`, `ensureGitHooks`) + `ScaffoldTemplates.swift` (`exampleUseCase`) + `WorkspaceScaffold.swift` |
| `packages/core/src/markers/cli/bind.ts` | `UseCasesCore/…/Markers/Commands/BindCommand.swift` |
| `packages/core/src/markers/cli/rebind.ts` | `UseCasesCore/…/Markers/Commands/RebindCommand.swift` |
| `packages/core/src/markers/cli/shared.ts` | `UseCasesCore/…/Markers/Commands/MarkerCommandInputs.swift` (`SourceWalk.isNestedWorkspace`, `workspaceConfigurationFiles`) |
| `packages/core/src/markers/cli/unbind.ts` | `UseCasesCore/…/Markers/Commands/UnbindCommand.swift` |
| `packages/core/src/markers/cli/verify.ts` | `UseCasesCore/…/Markers/Commands/VerifyRun.swift` (`plan`, `verify`, `verifyUnit`, `attest`, `VerificationResultsLedger.merge`) + `VerifiedRowInputs.swift` (`VerifyUnit.units`) |
| `packages/core/src/markers/freshness.ts` | `UseCasesCore/…/Markers/Freshness.swift` (`acceptanceClaim`) + `FreshnessRenames.swift` (`infer`) |
| `packages/core/src/markers/registry.ts` | `UseCasesCore/…/Markers/BindingRegistry.swift` (`validate`) |
| `packages/core/src/markers/verifierPresets.ts` | `UseCasesCore/…/Markers/VerifierPresets.swift` (`isTestSuitePreset`, `testSuitePresets`) |
| `packages/core/src/skills/validateSkillAssets.ts` | `UseCasesCore/…/Skills/SkillHostRegistration.swift` (`validate`, `declaredSkillRoots`) |
| `packages/core/src/useCases/integrity.ts` (`buildMatrixSnapshot`) | `UseCasesCore/…/UseCases/MatrixSnapshot.swift` (`init(context:files:candidates:diagnostics:)`, `RowGrouping`) |
| `packages/core/src/useCases/query.ts` | `UseCasesCore/…/UseCases/UseCaseQuery.swift` (`queryUseCases`) |
| `packages/mcp/src/toolSchemas.ts` | `UseCasesMCP/…/Tools/McpToolSchemas.swift` |
| `packages/core/test/init/scaffold-{agents-md,git-hooks}.test.ts` | `UseCasesCore/Tests/…/Initialization/WorkspaceScaffoldTests.swift` |
| `packages/core/test/init/scaffold-sample.test.ts` | `UseCasesCore/Tests/…/Initialization/ScaffoldedWorkspaceTests.swift` |

### Numbers

`verify --repo . --all` through the built Swift binary: **89 behaviours, 89
passed**, in **203s on the first run** (cold SwiftPM caches after the rebinds)
and **178s on the second** (warm). The TypeScript-era run was 89/89 in 2m46s, so
86 `swift test` spawns cost roughly 10-40s more depending on cache state.
`verify` runs verifiers sequentially — no `TaskGroup`, no `async let` in
`VerifyRun` — so the SwiftPM build lock is never contended, which is the new
failure mode a parallel `verify` would have introduced.
`scan --repo . --gate --policy-mode feature` exits 0;
`validate-ledger --base-ref HEAD --public-key …` exits 0, so the ~240 appended
binding events are append-only.

Mutation-proved, each broken at an ASSERTION, watched fail through
`verify --row`, restored and re-verified: `matrix.core.validate` (Oracle/Cli),
`mcp.surface.write_gating` (Oracle/Mcp),
`release.distribution.release_publishes_checksummed_assets` (Oracle/Plugin),
`plugin.init.vends_sample_matrix` and `plugin.init.wires_git_hooks` and
`evidence.ledger.crash_durable_ledger_writes` (UseCasesCore). The
`UseCasesCLI` selector was proved the same way one level down —
`ShowcaseCommandsGoldenCorpusTests` goes from 2 passed to 2 failed with 610
issues — because its row is UNBOUND and `verify` will not run it.

## Row 10d — the TypeScript is deleted

### Three rows retired, one row given a Swift carrier

The owner's two decisions for this row, and the third retirement they implied,
were all carried out BEFORE anything was deleted, so no row spent a moment
unproven.

- **`skills.assets.demo_gates` has a Swift carrier that reads the LIVE skill.**
  `UseCasesOracle/Tests/OracleTests/Cli/SkillsAssetsDemoGatesTests.swift`, five
  tests in one suite, reading `skills/showcase/SKILL.md` off
  `OracleLayout.repositoryRoot` — the same shape `PluginInitLoopSkillTests` and
  `AgentsRosterTests` already use for the live `skills/` and `agents/` trees.
  `SkillsGoldenCorpus` pins a FROZEN snapshot and cannot see an edit to a real
  skill body; this file can. The row was rebound onto it through the CLI and its
  verifier re-pointed to
  `swift test --package-path UseCasesOracle --filter SkillsAssetsDemoGatesTests`
  (run and read: **5 tests in 1 suite**, not trusted from the string). Its
  `inputs` name the test AND `skills/showcase/SKILL.md`, so editing the skill
  moves the row's verification context hash as well as failing the test.
  **Mutation-proved:** changing "A question NEVER rides in the same message as
  its card" to "A question may ride in the same message as its card" in the real
  skill fails the suite with
  `skills/showcase/SKILL.md must still say a question never rides in the same
  message as its card (/(?i)never rides in the same message/)`; reverted and
  green again. A second mutation ("The card grows; it never mutates." →
  "The card is replaced each turn.") failed a second test, so more than one
  assertion bites.
- **`diagnostics.contracts.missing_build_hint` is RETIRED.** Its behaviour
  cannot exist once Core is linked statically. `unbind --reason row_retired`
  first, then the row text removed from `use-cases/diagnostics/contracts.yml`.
- **`plugin.bundle.runs_from_clean_clone` is RETIRED** (both bindings — the
  `#bundler` one on `scripts/bundle.mjs` and the bare one on the test), and
  `use-cases/plugin/bundle.yml` was the only row in its feature file, so the
  file went whole — the same shape row 2a used for `use-cases/migration/`.
- **`plugin.runtime.pre_swift_versions_run_the_committed_bundle` is RETIRED**
  with `dist/`, and the resolver's Node branch and the bootstrap's
  `fallback_hint` went in the same edit.

Six further bindings were released with
`unbind --reason "row 10d: the TypeScript is deleted; the Swift oracle span
carries the row"`: every one was a DUPLICATE of a span the row already had in
Swift (10c's list, re-measured here rather than trusted —
`agents.roster.bodies_hold_the_line#bodies`,
`agents.roster.command_allowlist_tracks_cli`,
`agents.roster.shipped_with_plugin`, `plugin.init.loop_skill_ported`,
`plugin.install.claude_from_github`, `skills.assets.host_declaration`).

**112 bindings before, 102 after** (11 in doomed paths − 1 rebound onto Swift).
**118 rows before, 115 after.**

### What drove the CLI, and why it could not be `./bin/use-cases`

Every bind, rebind and unbind ran through
`UseCasesCLI/.build/out/Products/Debug/use-cases`, the built Swift binary, and
all of them ran BEFORE `dist/` was deleted. `bin/use-cases` at 0.7.0 resolves
through `bin/use-cases-runtime`, which below `FIRST_SWIFT_RELEASE` used to exec
the committed bundle and now refuses outright — so after this row the wrapper
cannot drive the matrix in this checkout at all, and the built binary is the
only honest answer. `.github/workflows/swift.yml` already gates with the built
binary for exactly this reason (10b's third guard).

### `source_refs` were left alone, deliberately, and it is measured

**119 references to `packages/**` survive across 25 row files.** They are
documentation pointers, and the check that settles it was run rather than
assumed: two `source_refs` in `use-cases/hosts/retired.yml` ALREADY name
`tests/conformance/bootstrap/agent-hook-installer.test.ts` and
`scripts/install-agent-hooks.mjs`, neither of which has existed for some time,
and `matrix validate --repo .` answers `valid: true` with the integrity state
`clean`. A dangling `source_refs` path is not an error, is not proof, and is not
read by `impact` — which maps BINDINGS to rows. Repointing all 119 would have
rewritten 25 row files and moved every one of their `row_hash`es on the most
dangerous row of the ladder, for no change in what is proved. 10c's
`packages/` → Swift mapping table is still the one a later pass needs; only
`skills.assets.demo_gates`'s own ref was repointed here, because that row was
being edited anyway.

Verifier `command`s and `inputs` are the opposite case and did all move: those
feed the verification context hash and are proof machinery.

### The deletion, and the two things that came back

Deleted with `git rm -r` so every removal is staged and reviewable:
`packages/`, `tests/` (except the fixtures, below), `dist/`, `package.json`'s
build half, `pnpm-lock.yaml`, `pnpm-workspace.yaml`, `vitest.config.ts`,
`tsconfig.json`, `tsconfig.base.json`, `scripts/bundle.mjs`,
`scripts/capture-cli-contract.mjs`, `scripts/use-cases-precommit.sh`,
`.github/workflows/ci.yml`, and the **20 `.mjs` corpus generators** under
`UseCasesCLI/Scripts`, `UseCasesCore/Scripts` and `UseCasesMCP/Scripts`.
`node_modules/` and the empty `packages/` shell were untracked and removed with
`rm -rf` after checking each path was non-empty, existed, lay under the
repository root and was no longer tracked.

Two things did NOT go:

- **`tests/fixtures/` came back, and had to.** `SchemaCommands.defaultFixture`
  is the literal string `tests/fixtures/workspaces/minimal-valid` — PRODUCT
  behaviour, frozen by decision 8 and recorded in the CLI dispatch corpus — and
  `FixtureWorkspaceValidatorTests` (15 assertions across 8 tests) validates that
  workspace and its siblings. Deleting them broke 15 Core tests and 3 CLI
  corpus cases; restoring the 55 data files fixed all 18. `backcompat/` came
  back with them: row 9 calls it the highest-value item on its left-undone list
  and nothing else preserves a capture of a published 0.5.5 binary.
  `tests/fixtures/README.md` now says why the directory outlived its tests.
- **`scripts/check-scenario-conventions.mjs` stayed.** It imports no TypeScript,
  reads only `use-cases/`, and `docs/rewrite/scenario-conventions.md` names it
  as the enforcement of the scenario naming convention. It is Node, but it is
  not the TypeScript toolchain.

### The corpus generators are gone, and the corpora are now the source of truth

All 20 ran the built TypeScript and refused to run against a `dist` older than
its `src`; with `packages/` gone they could not have worked. Each of the 21
corpus files whose header said `Regenerate with: pnpm … / node …/generate-*.mjs`
now says NOT REGENERABLE, names the generator that was retired, and says the
bytes are the record of what the TypeScript answered.

**This lands on row 11.** Row 6's note says the tool version is embedded in
several corpora — `created_by.version`, 72 occurrences in the marker-commands
corpus alone — and "regenerate them, don't hand-edit". There is nothing left to
regenerate them WITH, and there would not have been either way, because the
oracle they ran was the TypeScript. The 0.8.0 bump is now a deliberate,
reviewed search-and-replace over the corpora. Worth the owner knowing before
row 11 starts.

`UseCasesCore/Scripts/generate-embedded-schemas.swift` is the one generator that
survives: it is Swift and reads `schemas/`. Re-run here, it reproduced
`EmbeddedSchemas.swift` byte for byte and changed only the two path comments in
`EmbeddedMarkerSchemas.swift`.

### The three internal marker schemas MOVED rather than died

Row 10's note said the drift test's input "must move" once `packages/` goes. It
moved: `packages/core/src/markers/schemas/*.json` →
**`schemas/markers/`**, a sibling of the published `schemas/v1`. Checked first
that nothing enumerates `schemas/` wholesale — `SchemaRegistry`,
`SchemaFixtures`, the MCP resource reader and the generator all name
`schemas/v1` exactly — so the new directory cannot leak into the 27 published
ids. `EmbeddedMarkerSchemasTests` passes against the new path, and it is still
the only thing stopping the embedded copies and the committed files parting.

### What the deletion broke, all of it found by running things

The compiler finds none of this: every one of these reads a shipped file by path
at RUN time.

1. **`FixtureWorkspaceValidatorTests` — 15 issues** and **`DispatchGoldenCorpus`
   — 3 cases** (`schema_validate_fixtures_{valid,invalid_json,invalid_text}`).
   Cured by restoring `tests/fixtures/`, above.
2. **`PublicErrorRegistryTests.the rendered page equals the TypeScript
   renderer's output`.** `ErrorCodesDocument` EMITS a generated-file header into
   `docs/reference/error-codes.md` naming
   `node packages/core/scripts/generate-error-codes.mjs` and
   `packages/core/src/errors/registry.ts` — product output pointing at deleted
   files. The header now names `ErrorCodesDocument.render()` and
   `PublicErrorRegistry.swift`, the committed `.md` was updated to match, and
   the test was split: the page's BODY is still compared to the TypeScript's
   bytes exactly, and the header is asserted separately. The sibling test
   (`equals the committed docs/reference/error-codes.md byte for byte`) is
   untouched and still the real gate.
3. **`BootstrapFailuresTests.an asset the release does not carry …`** asserted
   the failure message named `dist/uc.js` AND that the path existed. Both are
   now inverted: the message must NOT contain `dist/` or "still available". The
   row `release.distribution.failed_download_says_what_to_do` lost its
   "Where a Node bundle is still present the message names it" outcome to match.
4. **`SessionPathTests`, two executions** (10b predicted one; there were two).
   `bin-use-cases runs the resolved runtime from any working directory` now
   publishes a stand-in release and asserts the STAND-IN executable answered
   from a directory that is not the repository — a stronger assertion than the
   old envelope parse, and gated on Apple Silicon like every other download
   test. The second was the `source env.sh && command -v use-cases &&
   use-cases version --json` probe inside `with CLAUDE_ENV_FILE set …`; the
   execution was dropped there (the sibling test covers it hermetically) and the
   probe now proves only what that test is about — the exported PATH resolving
   the command. `ReleaseStandIn.run` gained a `cwd:` parameter for this.
5. **`ReleaseWorkflowTests` and `CiWorkflowTests` both read `ci.yml`** (10b
   flagged both). `ReleaseWorkflowTests` now reads `swift.yml` and
   `use-cases.yml` and keeps the load-bearing half — no second workflow learns
   to cut a release — with `swift.yml` being exactly the tempting place.
   `CiWorkflowTests` dropped the `ci.yml` half and gained the inverse guard: no
   STEP of the gate may name `pnpm` or `vitest`. Asserted over the PARSED steps,
   not the file text, because the header comment explains what was removed and
   naming it there is the point.
6. **`.githooks/{pre-commit,pre-push}` both ran `node $root/dist/uc.js`.** They
   now resolve `$USE_CASES`, then this checkout's own
   `UseCasesCLI/.build/out/Products/Debug/use-cases`, then `use-cases` on PATH.
   Nothing found is a warning and exit 0, not a block — the same contract the
   product's own scaffolded hook has, and a fresh clone has built nothing yet.
7. **Every verification context hash moved**, as row 10's note predicted:
   `VerificationContextHash` hashes `pnpm-lock.yaml` by default and the file is
   gone. Expected, not breakage; `verify --all` recovers it in one pass.

### What still says `pnpm`, `vitest` or `packages/`, and why

- **Product support for Node projects, and it must stay.** `VerifierPresets`
  ships `js.vitest` / `js.npm-test`; `ScaffoldTemplates` writes
  `npx vitest run …` for `--template js-vitest`; `VerificationContextHash`
  hashes `pnpm-lock.yaml` by default; `common.schema.json` carries a `pnpm`
  example. These are how the tool verifies SOMEBODY ELSE'S repository. Decision
  8 freezes the schema and the presets. `docs/concepts/verifiers.md`,
  `docs/getting-started.md`, `docs/cli.md`, `docs/concepts/evidence.md`,
  `docs/README.md`, `docs/tutorials/python-pytest.md` and `DESIGN.md` document
  them, and were deliberately not touched.
- **Provenance comments in the Swift sources.** Roughly 150 files carry a
  `packages/…` line saying where the behaviour came from. They are records of
  the port, the same category as this file and the ADR; editing them would
  churn span hashes on bound rows for nothing.
- **`source_refs`**: the measured 119, above.
- **`marker.schema.json`'s description** names
  `packages/core/src/markers/constants.ts`. A published schema, frozen by
  decision 8 — it cannot be edited, and that is the right answer.
- **Records**: `docs/adr/`, `docs/acceptance/0.3.0/`, `docs/rewrite/`,
  `showcase-runs/`, `evidence/`, the two `.use-cases/` ledgers, and the
  `hosts/retired.yml` rows' vitest verifiers (three `lifecycle: removed` rows
  that nothing ever runs, two of which already named a file that does not
  exist). Left as history; the owner authorised three retirements, not four.
- **`bin/use-cases-runtime`'s comment** says what row 10d removed. One line.

### The AUTHORITY workflow was broken too, and is rewritten — unproven

`.github/workflows/use-cases.yml` is what mints FRESH: `validate-ledger`, `scan`,
and the release-only `verify → prove → persist → release gate`. Every one of its
three jobs began `corepack pnpm install --frozen-lockfile` + `corepack pnpm build`
and drove the CLI as `corepack pnpm cli -- …`. After this row all of that fails
at the first step, which would mean **no row could ever reach FRESH again**. The
brief did not name this file; `rg pnpm .github/` found it.

Rewritten: each job builds the CLI from source, exports the path through
`GITHUB_ENV`, and runs `"$USE_CASES" …`; the three toolchain jobs move to
`macos-15`, the platform ADR 0007 decision 6 pins and the label `swift.yml` and
`release.yml` already use (the `policy` job needs no toolchain and stays on
ubuntu). The `prove` job gains `setup-node`, because `verify --all` runs
`OpencodePluginTests`, which executes `opencode/plugin.js` — the one remaining
reason this repository needs a JavaScript runtime at all.

**Unproven until GitHub runs it**, the same disclosure 10b made for `swift.yml`.
Nothing here can fire it, no Swift test reads it (`ReleaseWorkflowTests` only
greps it for `gh release`), and the `verify --all` step it contains has only ever
been run by hand, from a local checkout, against a built binary.

### Two traps this row hit, both worth carrying forward

- **A hand-edited row file can break YAML and `verify` will say something
  else entirely.** Rewriting one outcome in `use-cases/release/distribution.yml`
  to `- It offers no alternative runtime, because there is none: the message is
  the whole answer.` made YAML read it as a MAPPING (the unquoted `": "`), so the
  file stopped loading, four `release.distribution.*` rows became
  `ROW_NOT_FOUND`, and `verify --repo . --all` answered
  **`no bound behaviours to verify`, exit 4** — a message that says nothing about
  YAML. `matrix validate --repo .` names the real fault immediately. Run it after
  every hand edit to a row file, not once at the end.
- **`validate-ledger --base-ref` is silently vacuous, and it is PRE-EXISTING.**
  The append-only check does `git show <ref>:<path>` with an ABSOLUTE path, which
  git always refuses (`fatal: path '…' exists on disk, but not in 'HEAD'`);
  `AppendOnly.isAbsentAtBase` matches exactly that wording, returns `""`, and the
  check then compares the ledger against an EMPTY base — which can only pass.
  Measured here on both ledgers. It is a faithful port of the TypeScript, so
  decision 8 covers it and it was NOT fixed in this row, but the consequence is
  that `append_only: true` in CI today proves nothing. Owner's call.

### Docs repointed

`AGENTS.md` (the `pnpm build` discipline line → the Swift packages and the
now-frozen corpora), `CONTRIBUTING.md` (setup, layout table, Green CI),
`README.md` (the quickstart's "runs the committed bundle" promise, the npm
Trusted Publishing line, the packaging paragraph),
`docs/reference/stability.md` (the workspaces line, and "Supported
environments: Node — active LTS" which was simply false),
`docs/markers-adoption.md` (two dead paths).

### A retired row with LEDGER HISTORY cannot simply vanish

This is the one place the brief's instruction ("retire it the way 2a did — the
row goes") could not be followed literally, and the repository's own rule is
what settled it.

Deleting the row TEXT for `diagnostics.contracts.missing_build_hint` and
`plugin.bundle.runs_from_clean_clone` left signed PROOF events in
`.use-cases/proofs.jsonl` naming rows the matrix no longer knows: six for the
first, one for the second. `validate-ledger` reports `EVIDENCE_ROW_MISSING`,
the evidence ledger is INVALID, and `verify --all` refuses to run at all —
answering `no bound behaviours to verify`, exit 4. The proof ledger is
append-only and signed, so the lines cannot be removed to suit the matrix.

`use-cases/hosts/retired.yml` states the rule in its own header, from the npm
retirement of 2026-09-16: rows "stay in the matrix as lifecycle: removed so the
evidence ledger's history for them remains valid; nothing binds to them and
nothing is verified against them." 2a could delete its five `migration.*` rows
outright only because none had ever been proven.

So the retirement is history-driven, and each file says which it got:

| row | proof events | treatment |
|---|---|---|
| `diagnostics.contracts.missing_build_hint` | 6 | `lifecycle: removed`, kept in `use-cases/diagnostics/contracts.yml` |
| `plugin.bundle.runs_from_clean_clone` | 1 | `lifecycle: removed`, `use-cases/plugin/bundle.yml` restored for it |
| `plugin.runtime.pre_swift_versions_run_the_committed_bundle` | 0 | row text removed, 2a's shape |

All three were released with `unbind --reason row_retired` first, whichever way
they went. The two surviving rows keep their `pnpm -s vitest` verifiers and
their `dist/` prose exactly as they were: a `removed` row is never verified, and
rewriting a record of what was once true would be the dishonest edit — the same
reasoning `hosts/retired.yml` already stands on. **The matrix is 117 rows: 115
live plus these 2 records.**

### Numbers

Measured on 2026-09-18 against the built Swift binary
(`UseCasesCLI/.build/out/Products/Debug/use-cases`), never `bin/use-cases`.

- **Suites, all green:** UseCasesCore **605** tests in 95 suites; UseCasesCLI
  **45** in 17; UseCasesMCP **28** in 5; UseCasesOracle **298** in 81 (17
  skipped — 10a's six todos, 10b's three `live:` cases, and the Apple-Silicon
  trait where it does not apply). The oracle was **293** before this row; the
  five new ones are `SkillsAssetsDemoGatesTests`.
- **`verify --repo . --all`: 86 behaviours, 86 passed, exit 0, 225s.** 89 before,
  minus the three retired rows.
- **`scan --repo . --gate --policy-mode feature`: exit 0, gate passed** — 3
  required behaviours meet VERIFIED_LOCAL. 117 rows, 102 bindings, **0 integrity
  errors**. Summary: 76 verified_local, **0 stale_local**, 72 unproven, 34
  unbound, 11 suspect, 0 invalid, 0 policy_blocked. The `stale_local: 0` is the
  measurement that matters here: deleting `pnpm-lock.yaml` moved every
  verification context hash (73 rows read `stale_local` immediately after), and
  ONE `verify --all` pass recovered all of them, exactly as row 10's note
  predicted. The 11 SUSPECT rows are stale SIGNED proofs, pre-existing and
  ungated.
- **`validate-ledger --repo . --base-ref HEAD --public-key
  .use-cases/trusted-ci-public-key.pem`: exit 0** — evidence valid, registry
  valid, 139 proof events, 371 registry events, chain verified over all 139
  entries with no legacy prefix, 0 errors. (With the append-only caveat above.)
- **`swiftformat --lint .`: 0/610 files require formatting.
  `swiftlint lint --strict`: 0 violations, 0 serious, in 610 files.**

### The clean-clone proof

`git ls-files -z` piped through `tar` into a `mktemp` sandbox — exactly the
tracked tree a fresh clone gets, taken from the working tree — then built and
driven there. **840 files.** None of `packages/`, `tests/agents`, `tests/cli`,
`dist`, `pnpm-lock.yaml`, `pnpm-workspace.yaml`, `vitest.config.ts`,
`tsconfig*.json`, `node_modules` or `.github/workflows/ci.yml` is present.

- the three products build from cold (9.2s, 8.7s, 8.9s);
- the built CLI answers `version --json` and `matrix validate --repo . --json`
  (`valid: true`) inside the sandbox;
- `scan --repo . --gate` exits **1** there, and that is correct rather than a
  regression: `.use-cases/verification-results.jsonl` is gitignored, so a clean
  clone has no local ✓ ledger until it runs `verify` itself — 10b recorded the
  same thing for CI;
- all four suites pass from the clean copy: **605 / 45 / 28 / 298**;
- **the plugin's entry points fail HONESTLY.** At 0.7.0, with no Swift release
  in existence, `./bin/use-cases version` exits 1 with
  `release v0.7.0 publishes no use-cases binary, and this plugin no longer
  carries a fallback runtime. / Install a release from 0.8.0 on, or set
  USE_CASES_VERSION to one.` — and `./bin/use-cases-mcp` says the same for its
  own executable. Forced to a Swift-era version against a release that does not
  exist, the bootstrap refuses at the checksums:
  `release v0.8.0 published no checksums … / Refusing to run an unverified
  binary.` That is the expected 0.7.0 behaviour after this row, not breakage;
- `hooks/session-start` exits 0 and still delivers the bootstrap
  (`<EXTREMELY_IMPORTANT>` …);
- `node` loading `opencode/plugin.js` registers `mcp:use-cases` and all five
  skills (`init`, `showcase`, `use-case-driven-development`, `use-cases`,
  `walkthrough`) — the minimal `package.json` still resolves the module.

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

### The marker AND the verifier both have to move (measured in row 9, 2026-09-18)

Rebinding a row is only half the job: every row's verifier still runs
`pnpm -s vitest …`. A row whose marker moves onto Swift while its verifier runs
a deleted suite goes green having proved nothing.

Measured from `scan --json` `current_bindings[].file_path` and the rows' own
`verification_policy.verifiers`, over 117 rows:

- **29 rows are bound into `packages/`**; 24 of them are ALSO bound into
  `tests/blackbox/`, so for those the rebind is "drop the `packages/**/src`
  span, keep the black-box one". Five are bound ONLY into `packages/`:
  `diagnostics.contracts.missing_build_hint`,
  `evidence.ledger.crash_durable_ledger_writes` and the three `plugin.init.*`
  below.
- **Only 3 marker spans live in a `packages/*/test` file at all**:
  `packages/core/test/init/scaffold-{agents-md,git-hooks,sample}.test.ts`.
- **8 rows have a verifier COMMAND naming a `packages/*/test` file.** These are
  the ones that silently lose their proof, and five of them are **unbound**, so
  nothing in `scan` will flag them:

  | row | verifier names | Swift carrier | `--filter` selector |
  |---|---|---|---|
  | `plugin.init.records_decision_in_agents_md` | `…/init/scaffold-agents-md.test.ts` | `WorkspaceScaffoldTests` + `InitializationGoldenCorpus` `agents_md_*` | `swift test --package-path UseCasesCore --filter WorkspaceScaffoldTests` |
  | `plugin.init.wires_git_hooks` | `…/init/scaffold-git-hooks.test.ts` | `WorkspaceScaffoldTests` + `configured_hooks_path_*` | same |
  | `plugin.init.vends_sample_matrix` | `…/init/scaffold-sample.test.ts` | `ScaffoldedWorkspaceTests` (new in row 9) | `swift test --package-path UseCasesCore --filter ScaffoldedWorkspaceTests` |
  | `signing.tier.keygen_keeps_the_private_key_out_of_the_tree` (UNBOUND) | `…/markers/keygen.test.ts` | `SigningKeyGenerationTests` | `swift test --package-path UseCasesCore --filter SigningKeyGenerationTests` |
  | `signing.tier.prove_never_signs_what_it_cannot_recompute` (UNBOUND) | `…/markers/prove{Consumes,Authority}.test.ts` | `VerifyProveTests` (`proveCaseNames`) | `swift test --package-path UseCasesCore --filter VerifyProveTests` |
  | `signing.tier.validate_ledger_holds_the_append_only_line` (UNBOUND) | `…/markers/ledgerChainValidate.test.ts` | `EvidenceLedgerTests` + `LedgerChainRulesTests` (new in row 9) | `swift test --package-path UseCasesCore --filter EvidenceLedgerTests --filter LedgerChainRulesTests` (two flags — see the trap below) |
  | `signing.tier.recover_never_fakes_green` (UNBOUND) | `packages/cli/test/commands/recoverVariants.test.ts` | `MarkerCommandsGoldenCorpusTests` case `recover_variant_family` | `swift test --package-path UseCasesCLI --filter MarkerCommandsGoldenCorpusTests` |
  | `signing.tier.approve_run_keeps_the_key_out_of_agent_scope` (UNBOUND) | `packages/cli/test/commands/approveRun.test.ts` | `ShowcaseCommandsGoldenCorpusTests` | `swift test --package-path UseCasesCLI --filter ShowcaseCommandsGoldenCorpusTests` |

  Every selector above was run in row 9, in exactly the `--package-path` form
  written, and each selects a non-zero number of tests — in table order: 8, 8,
  5, 4, 3, 9, 4, 2.

- **TRAP: `swift test --filter` matching nothing exits 0.** Measured:
  `swift test --package-path UseCasesCore --filter 'EvidenceLedgerTests\|LedgerChainRulesTests'`
  prints `warning: No matching test cases were run` and **exits 0** — so a
  verifier whose selector is misspelled records a PASS having run nothing. That
  is the same silent-green this whole table exists to prevent, and there is no
  guard against it: a selector is a string in a YAML file.
  Two ways to get it wrong that were both hit here:
  `--filter` takes an ICU regex, so `\|` is an escaped LITERAL pipe and matches
  no suite; and a bare `|` cannot sit in a markdown table cell. **Pass `--filter`
  twice instead of alternating** — repeated flags union their patterns
  (measured: 9 tests in 2 suites). Run every selector once after editing it and
  read the test COUNT, not the exit code.

- **80 rows name a `packages/**` path in `source_refs`.** Those are
  documentation pointers, not proof, but they all rot at row 10 and should be
  repointed onto the Swift sources in the same pass.
- **Verifier inputs move too.** The three `plugin.init.*` verifiers list
  `packages/core/src/init/scaffold.ts` as an input, which feeds the
  verification context hash. Swapping the command without swapping the inputs
  leaves the hash pinned to a deleted file.

## Row 9 — the white-box TypeScript tests, carried into Swift

### The count is 133, not 87

ADR 0007's consequences section estimated "~87 white-box files"; it also says
the count is measured, not assumed. Measured 2026-09-18: **155 test files total**
(the number `pnpm test` reports), of which **22 are the black-box oracle**
(everything in `tests/blackbox/`, 21 reaching the product through
`tests/helpers/{uc-binary,mcp-server}.ts` and `plugin-install-claude.test.ts`
reaching only the shipped manifests). That leaves **133 non-black-box files**:
72 under `packages/*/test/**` and 61 under `tests/**`. The ADR's estimate
predates the suite growth decision 2 caused; the delta is growth, not an error.

### Three buckets were not enough — there is a fourth

`tests/plugin/*`, `tests/conformance/bootstrap/session-start.test.ts` and
`tests/skills/init-skill.test.ts` test bash scripts, YAML manifests and
markdown — they import no TypeScript at all and are untouched by deleting
`packages/`. They are **SURVIVES-ROW-10**, not "dies with the TypeScript".
They do still need the vitest harness, which is the owner question below.

### Findings

- **A derived freshness status can fail its own published schema, and the
  TypeScript's does too.** Nothing on either side ever validated a DERIVED
  status, so this was invisible. Two shapes are refused by
  `ucase-freshness-status-v1`: a row carrying `variant_local_status`
  (`/rows/0` "must NOT have additional properties" — the schema has no member
  for the variant roll-up) and a row whose `row_id` is the empty string
  (`/rows/0/row_id` "must NOT have fewer than 1 characters"). Measured by
  feeding the corpus's own node-recorded wire back through node's
  `validateFreshnessStatus`: node gives the identical verdict and the identical
  message. Same class as the "presentation plans can fail their own published
  schema" note above — decision 8 freezes both the schema and the behaviour and
  they disagree. Pinned as is by `FreshnessContractTests`, which asserts the
  RULE (these two shapes are refused, everything else validates) so a third
  shape starting to fail still breaks the suite. **Owner's call** which side is
  wrong.
- **A whole CLI rendering branch was dead to the suite.** No recorded corpus
  case carries a non-empty `gate.ungated_below_bar`, so the
  "⚠ `<row>` is `<state>` but NOT gated" warning loop in
  `TrustRenderer+Scan.swift` could have been deleted with every test still
  green. Now pinned by `TrustRendererGateTests`.
- **The row 4c note "nothing was ported for `precommit`" is half wrong.** It is
  true of the CLI surface — `precommit` is not a command — but `Precommit.decide`
  and `Precommit.pullRequestSummary` ARE ported and pinned by 20 corpus cases in
  `ScanImpactGoldenCorpus.precommitCaseNames`. Only
  `scripts/use-cases-precommit.sh` itself dies at row 10.

### Written in row 9

Four new Swift test files, 15 test functions (154 test cases with
parameterisation), all mutation-proven:

- `UseCasesCore/…/Initialization/ScaffoldedWorkspaceTests.swift` — the vended
  sample's SHAPE (a scenario of each kind, a comment above every documented
  field, "one test"), and that a freshly scaffolded workspace loads, validates
  clean and scans with every row UNBOUND and nothing INVALID. The init corpus
  records the scaffolded bytes; no case had ever read the tree back as a
  workspace. This also closes one of the two gaps in
  `tests/conformance/cli/init-contract.test.ts` ("the scaffolded workspace
  immediately passes `matrix validate`") — no `MatrixInitGoldenCorpus` case
  chains `init` to anything, they are all one argv. The other half of that file
  (the generated `use-cases.yml` and row file validating against
  `workspace-config.schema.json` / `use-case-file.schema.json`) is still open.
- `UseCasesCore/…/Markers/Commands/LedgerChainRulesTests.swift` — a chain break
  as the ONLY fault driving `validate-ledger` to exit 4 with just
  `UCM_LEDGER_CHAIN_BROKEN`, an untouched chain verifying all three entries, and
  a legacy proof with the chain fields stripped and re-signed still validating
  and still reading FRESH through `scan`.
- `UseCasesCore/…/Markers/FreshnessContractTests.swift` — the schema finding
  above, plus a keyless `scan` in feature mode exiting 0 with `evidence_valid`
  true (every recorded keyless case runs in release mode behind the gate, so the
  corpus only ever pinned exit 1), plus an unrecognised CI falling back to
  `local`/`generic` (every recorded `local` case passes an EMPTY environment).
- `UseCasesCLI/…/Rendering/TrustRendererGateTests.swift` — the dead warning
  branch above, including that the GATE's list decides, not the status rows'.

### Left undone, and it is a real list

Row 9 enumerated all 133 files but wrote tests for only the highest-value gaps.
The following behaviours are pinned by nothing in Swift today. None of them is
on a row whose verifier command names a `packages/` path, which is why they were
ranked below the eight rows above — but they all disappear with `packages/`.

- `lieGuard.test.ts`: an internally CONSISTENT unsigned proof (hashes all
  recompute, only `signature` absent) driven through `scan`; and the forbidden
  marker payloads `proven=true`, `row_hash=`, `span_hash=`, `role=`, `tier1`
  (only `sha256=` and `fresh=` are driven).
- `walkingSkeleton.test.ts`: the a–f ladder as ONE sequence (bind → UNPROVEN →
  prove → FRESH → edit the body → SUSPECT → reprove → FRESH → delete the marker
  → ALL_BINDINGS_REMOVED), and the re-slug + `--register-existing` pair read in
  one scan.
- `rebind.test.ts`: VERIFIED_LOCAL does not survive a rebind, and is restored by
  re-verifying; after an unbind nothing still claims it.
- `keyringFreshnessE2e.test.ts`: key ROTATION end to end — two active keys, a
  refresh-prove under the new one, the newest proof winning.
- `verify.test.ts`: a `--public-key` that RESOLVES but REJECTS, giving exit 4
  with `BAD_SIGNATURE` (the corpus only ever passes the right PEM or no key).
- `scanGate.test.ts`: a non-required VERIFIED_LOCAL row reported in
  `ungated_below_bar` under the RELEASE bar.
- `verificationPolicySchema.test.ts` / `workspaceConfigVerifiersSchema.test.ts` /
  `v1NewSchemas.test.ts`: the accept/reject pairs for verifier `kind`, preset
  references, unknown preset ids, `default` values, and the `authority`,
  `ledger`, `release-gate-result` and `approval-token` refusals.
- `markers.test.ts`: the marker/registry/proof schemas refusing their
  required-property and enum violations (today only the ledger RULES are
  pinned, so a schema regression would pass).
- `approvalTokenAppend.test.ts`: the replay regression guard — a hand-written
  `approval_recorded` with `capture_method: trusted_user_interactive_cli` and no
  token must be IGNORED; and the accept direction of a lowered assurance floor.
- `showcaseApprove.test.ts`: approving an epoch-staled run exits non-zero in
  both modes; a lowered floor end to end through the CLI; `--keyring` narrowing
  to a pinned SUBSET and succeeding.
- `matrixValidate.test.ts`: `approval_policy.minimum_assurance_tier` and
  `approval_trust.public_keys` validating clean through `matrix validate`.
- `useCases/matrix.test.ts`: the snapshot surfacing the workspace's pinned
  `approval_trust`. `useCases/variants.test.ts`: an illegal variant key making
  the row non-addressable.
- `scaffold-git-hooks.test.ts`: the EMITTED `.githooks/pre-commit`, run under
  bash with no `use-cases` on PATH, exits 0 and warns — nothing in Swift ever
  runs the script it writes. `scaffold-path-containment.test.ts`: an absolute
  `--repo` under a symlinked parent SUCCEEDS.
- `redact.test.ts`: the label's case is preserved (`API-KEY:` → `API-KEY=`);
  a short `AKIA` look-alike survives.
- `roots/idValidation.test.ts`: the runtime id regex and
  `common.schema.json#/$defs/id` do not drift apart.
- `ciAuthority.test.ts` is done; `ledgerChain.test.ts` is done.
- `mcp/showcaseRequestApproval.test.ts`: `exp` strictly after `iat` (the corpus
  normalises both away), and two requests minting distinct nonces.
- `tests/agents/canonical-agents.test.ts`, `tests/skills/{loop-skill,p7-skills}.test.ts`:
  the LIVE `agents/` and `skills/` trees. `SkillsGoldenCorpus` validates a
  FROZEN `shipped` snapshot embedded in the corpus, so editing a real skill or
  agent body today fails no Swift test. `agents/` is read by nothing in Swift at
  all.
- `tests/e2e/p11-product-lifecycle.test.ts`: the shipped `examples/` workspaces
  are referenced by zero Swift tests, and `examples/python-pytest` by nothing in
  either language.
- `tests/use-cases/compat/proof-survives-upgrade.test.ts`: the
  `tests/fixtures/backcompat/proven-0.5.5/` workspace — a real artifact of the
  published 0.5.5 binary — is touched by nothing in Swift. Its four literal
  hashes appear nowhere in the Swift tree. This is the upgrade contract, and it
  is the highest-value item on this list.
- `tests/use-cases/compat/ledger-migration.test.ts`: today's `bind` /
  `bind --register-existing` events still validating against the committed
  0.5.5 event schema, and that schema refusing `binding_released`.
- `tests/schema/{evidence,matrix,schema}-cli.test.ts`: each command's `data`
  against its OWN result schema (the envelope is pinned, the payload is not).
- `tests/schema/schema-contracts.test.ts`: a timestamp-looking YAML scalar
  (`name: 2026-06-25`) staying a string.
- `tests/plugin/claude-install.test.ts`: `plugin.json.name == "use-cases"`
  exactly, the `mcpServers` args being exactly the one-element array, and
  `.agents/skills` not existing.

And from `tests/cli/**` and `tests/conformance/**`, which mostly spawn a
hardcoded `node packages/cli/dist/index.js` and so cannot be re-pointed:

- **Nothing schema-validates real command output.** The CLI corpora compare
  bytes; `CliResultTests` validates one hand-built envelope. Uncovered: every
  command's real `--json` stdout against `cli-result.schema.json`, and each
  command's `data` against its own v1 data schema (matrix-mutation-result,
  evidence-append-result, showcase-*-result, presentation-plan-result, …), plus
  the gate that the set of commands exercised IS the canonical surface.
  (`cli-output-contract`, `p5-plan-contract`, `p6-showcase-contract`,
  `schema/{evidence,matrix,schema}-cli`.)
- **Two anti-drift joins have both halves in Swift and no test joining them.**
  `KnownCliCommands` (Core) × `CommandRegistry.allCommands` (CLI) — the
  skill/agent allowlist must equal what the registry dispatches; and
  `McpToolCatalog.descriptors` × `CommandRegistry.allCommands` — every MCP tool
  id must exist as a CLI command, and the CLI-only trust surface
  (`markers.bind`, `markers.scan`, `markers.verify`, `markers.validate-ledger`)
  must never become a tool. `rg KnownCliCommands UseCasesCLI UseCasesMCP` is
  empty today. Both tests need a target that can see both modules.
- **The `use-cases-mcp` EXECUTABLE has no test at all.** `McpGoldenCorpusTests`
  calls `McpStdioServer.response(to:)` in process; nothing launches the binary,
  so `--stdio`, newline framing over real pipes, silent
  `notifications/initialized`, id matching across interleaved lines,
  `result.structuredContent`, and "closing stdin ends the process" are pinned by
  nothing. (`p13-stdio-parity`.) The CLI has the equivalent already —
  `EvidenceVoidRaceTests` runs the real binary.
- **CLI/MCP envelope equality is asserted nowhere** — `matrix_validate` and
  `doctor_roots` over MCP versus the same commands on the CLI, and a missing
  repo giving a byte-identical `workspace.not_found` on both. (`p9-mcp`.)
- **Four MCP-surface path-safety cases** absent from `McpGoldenCorpus`:
  `showcase_record_observation` with a traversal `run` and with a traversal
  `item`, and `showcase_start` with an absolute out-of-workspace `plan_file`
  and with a `plan_file` symlink pointing outside. The CLI equivalents are
  pinned; the MCP ones are not.
- **A SUCCESSFUL `capsule_run` over MCP** — every `capsule_run` case in
  `McpGoldenCorpus` is a refusal. (`p14-mcp-capsule-runner`.)
- **The shipped `skills/use-cases/SKILL.md` is read by no Swift test** — same
  frozen-snapshot problem as the skills corpus. (`conformance/agents/skill-currency`,
  whose MCP-prompt half IS covered by `McpGoldenCorpus`.)
- **No Swift test runs a real verifier toolchain.** Four `tests/cli/*` files
  drive real `pytest` through `verify`/`recover`/`scan --gate`; every Swift
  verifier is a scripted stub, so `python.pytest`'s actual command line is
  proved nowhere. `examples/python-pytest` survives row 10 and is the fixture.
  Their `pnpm pack` → `npm install` → `node_modules/.bin` harness dies with the
  TypeScript regardless.

### Dies with the TypeScript, deliberately

- `tests/plugin/bundle.test.ts` and `tests/smoke/build-concurrency.test.ts` —
  the Node bundle and the `copy-schemas.mjs` race. Swift embeds the schemas;
  `EmbeddedSchemasTests` already carries the surviving idea.
- `tests/use-cases/compat/backcompat-contract.test.ts` — its capture script
  (`scripts/capture-cli-contract.mjs`) spawns `node <cli>` and cannot be
  re-pointed. The FIXTURE `contract-0.4.0.json` survives as data; only the
  mechanism dies. Whether the superset property is worth a Swift harness is an
  owner call.
- `tests/plugin/runtime-resolver.test.ts`'s second describe — already a planned
  retirement (see the row 10 note above).
- `errors/registry.test.ts`'s "throws for an unknown enum code" — unrepresentable
  in Swift. `markers.test.ts`'s "drops undefined-valued keys" — JS `undefined`
  has no `JSONValue`. `scaffold.test.ts`'s npm `files` set — npm went at 0.7.0.
- `packages/core/test/markers/precommit.test.ts`'s acceptance 7 only (the shell
  script's existence and exec bit).

### Owner question — does the vitest harness survive row 10?

The row 10 note says deleting the TypeScript toolchain deletes `pnpm-lock.yaml`.
If that means `package.json`, `pnpm` and `vitest` go too, then the 22 black-box
oracle files and the ~11 SURVIVES-ROW-10 files (the bash bootstrap, the host
manifests, the release workflow, the session hook, `opencode/plugin.js`, the
init skill) lose their runner as well, and each needs a Swift home — which is a
much larger job than row 10 as written, and is NOT row 9's. If instead the root
`package.json`/vitest stay as a test harness with `packages/` gone, those files
need no work at all. Row 9 did not pick a side.


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

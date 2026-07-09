# 0.3.0 Higher-Assurance Approval Tiers - Adversarial Live Acceptance

Run date: 2026-07-05

## SECURITY DEFECTS

None found. Every required attack was blocked/fail-closed.

## Scope And Setup

- Built the real CLI with `pnpm -r build`.
- Ran every acceptance command from `/Users/admin/repos/use-case-matrix-g2-attack` using `node packages/cli/dist/index.js`.
- Scratch workspace: `/tmp/uc-tiers-acceptance/workspace`.
- Did not run the unit suite or smoke test.
- Read schemas: `schemas/v1/keyring.schema.json`, `schemas/v1/workspace-config.schema.json`, `schemas/v1/approval-token.schema.json`.
- Pinned `approval_trust.keyring_path: trust/keyring.json` with ed25519 trusted/same-channel/automation keys plus a WebAuthn credential.

Note: thrown error envelopes report the CLI invocation cwd in `context`, but every attack command below passes `--repo /tmp/uc-tiers-acceptance/workspace` and operates on that scratch run ledger.

### Setup Output

#### `pnpm -r build`

```text
exit=0
Scope: 3 of 4 workspace projects
packages/core build$ tsc -b
packages/core build: Done
packages/mcp build$ tsc -b
packages/cli build$ tsc -b
packages/mcp build: Done
packages/cli build: Done
```

#### `node packages/cli/dist/index.js keygen --repo '/tmp/uc-tiers-acceptance/workspace' --out '/tmp/uc-tiers-acceptance/keys/trusted' --ci github --json`

```text
exit=0
{"schema_version":1,"protocol_version":1,"command":"markers.keygen","ok":true,"complete":true,"data":{"algorithm":"ed25519","private_key_path":"/tmp/uc-tiers-acceptance/keys/trusted/ci-signing-key.pem","public_key_path":"/tmp/uc-tiers-acceptance/keys/trusted/ci-signing-key.pub.pem","public_key":"-----BEGIN PUBLIC KEY-----\nMCowBQYDK2VwAyEAJiojwnAVHVHhkV+rvKhTNicehkQYyg5vuRCo22EIHek=\n-----END PUBLIC KEY-----\n","warning":"The private key is a CI secret: store it ONLY in your CI secret store (never commit it, never write it into the repo). Commit / distribute only the public key.","ci_snippet":"# .github/workflows/release.yml — sign use-cases proofs in CI\n#\n# 1. Add the PRIVATE key PEM as a repository secret named UCM_CI_SIGNING_KEY\n#    (Settings -> Secrets and variables -> Actions -> New repository secret).\n# 2. Commit the PUBLIC key (ci-signing-key.pub.pem) so scan/validate-ledger can verify.\n#\npermissions:\n  contents: read\n  id-token: write   # OIDC — no long-lived token needed\n\njobs:\n  prove:\n    runs-on: ubuntu-latest\n    steps:\n      - uses: actions/checkout@v4\n      - name: Mint signed proofs\n        env:\n          UCM_CI_SIGNING_KEY: ${{ secrets.UCM_CI_SIGNING_KEY }}\n        run: |\n          uc prove --all --trusted-ci \\\n            --signing-key-env UCM_CI_SIGNING_KEY \\\n            --key-id ci-key-1\n"},"diagnostics":[],"context":{"workspace_root":"/tmp/uc-tiers-acceptance/workspace","data_root":"/tmp/uc-tiers-acceptance/workspace","component_id":"use-cases","workspace_snapshot":{"repository_id":"unknown","vcs":"unknown","head_revision":"unknown","dirty":false,"working_tree_digest":"sha256:0000000000000000000000000000000000000000000000000000000000000000","component_id":"use-cases","captured_at":"1970-01-01T00:00:00.000Z"}}}
```

#### `node packages/cli/dist/index.js keygen --repo '/tmp/uc-tiers-acceptance/workspace' --out '/tmp/uc-tiers-acceptance/keys/wrong' --ci github --json`

```text
exit=0
{"schema_version":1,"protocol_version":1,"command":"markers.keygen","ok":true,"complete":true,"data":{"algorithm":"ed25519","private_key_path":"/tmp/uc-tiers-acceptance/keys/wrong/ci-signing-key.pem","public_key_path":"/tmp/uc-tiers-acceptance/keys/wrong/ci-signing-key.pub.pem","public_key":"-----BEGIN PUBLIC KEY-----\nMCowBQYDK2VwAyEAj9IpQpQlqWRR5qBmIh0VgOzJppZeJSBMYA4h8EpyZGk=\n-----END PUBLIC KEY-----\n","warning":"The private key is a CI secret: store it ONLY in your CI secret store (never commit it, never write it into the repo). Commit / distribute only the public key.","ci_snippet":"# .github/workflows/release.yml — sign use-cases proofs in CI\n#\n# 1. Add the PRIVATE key PEM as a repository secret named UCM_CI_SIGNING_KEY\n#    (Settings -> Secrets and variables -> Actions -> New repository secret).\n# 2. Commit the PUBLIC key (ci-signing-key.pub.pem) so scan/validate-ledger can verify.\n#\npermissions:\n  contents: read\n  id-token: write   # OIDC — no long-lived token needed\n\njobs:\n  prove:\n    runs-on: ubuntu-latest\n    steps:\n      - uses: actions/checkout@v4\n      - name: Mint signed proofs\n        env:\n          UCM_CI_SIGNING_KEY: ${{ secrets.UCM_CI_SIGNING_KEY }}\n        run: |\n          uc prove --all --trusted-ci \\\n            --signing-key-env UCM_CI_SIGNING_KEY \\\n            --key-id ci-key-1\n"},"diagnostics":[],"context":{"workspace_root":"/tmp/uc-tiers-acceptance/workspace","data_root":"/tmp/uc-tiers-acceptance/workspace","component_id":"use-cases","workspace_snapshot":{"repository_id":"unknown","vcs":"unknown","head_revision":"unknown","dirty":false,"working_tree_digest":"sha256:0000000000000000000000000000000000000000000000000000000000000000","component_id":"use-cases","captured_at":"1970-01-01T00:00:00.000Z"}}}
```

#### `node packages/cli/dist/index.js keygen --repo '/tmp/uc-tiers-acceptance/workspace' --out '/tmp/uc-tiers-acceptance/keys/same' --ci github --json`

```text
exit=0
{"schema_version":1,"protocol_version":1,"command":"markers.keygen","ok":true,"complete":true,"data":{"algorithm":"ed25519","private_key_path":"/tmp/uc-tiers-acceptance/keys/same/ci-signing-key.pem","public_key_path":"/tmp/uc-tiers-acceptance/keys/same/ci-signing-key.pub.pem","public_key":"-----BEGIN PUBLIC KEY-----\nMCowBQYDK2VwAyEASOiLvdbriPCEsFUoul7AAcgwJJ25gXrHEWLG2Ab8GBw=\n-----END PUBLIC KEY-----\n","warning":"The private key is a CI secret: store it ONLY in your CI secret store (never commit it, never write it into the repo). Commit / distribute only the public key.","ci_snippet":"# .github/workflows/release.yml — sign use-cases proofs in CI\n#\n# 1. Add the PRIVATE key PEM as a repository secret named UCM_CI_SIGNING_KEY\n#    (Settings -> Secrets and variables -> Actions -> New repository secret).\n# 2. Commit the PUBLIC key (ci-signing-key.pub.pem) so scan/validate-ledger can verify.\n#\npermissions:\n  contents: read\n  id-token: write   # OIDC — no long-lived token needed\n\njobs:\n  prove:\n    runs-on: ubuntu-latest\n    steps:\n      - uses: actions/checkout@v4\n      - name: Mint signed proofs\n        env:\n          UCM_CI_SIGNING_KEY: ${{ secrets.UCM_CI_SIGNING_KEY }}\n        run: |\n          uc prove --all --trusted-ci \\\n            --signing-key-env UCM_CI_SIGNING_KEY \\\n            --key-id ci-key-1\n"},"diagnostics":[],"context":{"workspace_root":"/tmp/uc-tiers-acceptance/workspace","data_root":"/tmp/uc-tiers-acceptance/workspace","component_id":"use-cases","workspace_snapshot":{"repository_id":"unknown","vcs":"unknown","head_revision":"unknown","dirty":false,"working_tree_digest":"sha256:0000000000000000000000000000000000000000000000000000000000000000","component_id":"use-cases","captured_at":"1970-01-01T00:00:00.000Z"}}}
```

#### `node packages/cli/dist/index.js keygen --repo '/tmp/uc-tiers-acceptance/workspace' --out '/tmp/uc-tiers-acceptance/keys/agent' --ci github --json`

```text
exit=0
{"schema_version":1,"protocol_version":1,"command":"markers.keygen","ok":true,"complete":true,"data":{"algorithm":"ed25519","private_key_path":"/tmp/uc-tiers-acceptance/keys/agent/ci-signing-key.pem","public_key_path":"/tmp/uc-tiers-acceptance/keys/agent/ci-signing-key.pub.pem","public_key":"-----BEGIN PUBLIC KEY-----\nMCowBQYDK2VwAyEAxgo92ft/ERppEgC1jCSDORR5Zq+pO6Cke2iURTpGfHA=\n-----END PUBLIC KEY-----\n","warning":"The private key is a CI secret: store it ONLY in your CI secret store (never commit it, never write it into the repo). Commit / distribute only the public key.","ci_snippet":"# .github/workflows/release.yml — sign use-cases proofs in CI\n#\n# 1. Add the PRIVATE key PEM as a repository secret named UCM_CI_SIGNING_KEY\n#    (Settings -> Secrets and variables -> Actions -> New repository secret).\n# 2. Commit the PUBLIC key (ci-signing-key.pub.pem) so scan/validate-ledger can verify.\n#\npermissions:\n  contents: read\n  id-token: write   # OIDC — no long-lived token needed\n\njobs:\n  prove:\n    runs-on: ubuntu-latest\n    steps:\n      - uses: actions/checkout@v4\n      - name: Mint signed proofs\n        env:\n          UCM_CI_SIGNING_KEY: ${{ secrets.UCM_CI_SIGNING_KEY }}\n        run: |\n          uc prove --all --trusted-ci \\\n            --signing-key-env UCM_CI_SIGNING_KEY \\\n            --key-id ci-key-1\n"},"diagnostics":[],"context":{"workspace_root":"/tmp/uc-tiers-acceptance/workspace","data_root":"/tmp/uc-tiers-acceptance/workspace","component_id":"use-cases","workspace_snapshot":{"repository_id":"unknown","vcs":"unknown","head_revision":"unknown","dirty":false,"working_tree_digest":"sha256:0000000000000000000000000000000000000000000000000000000000000000","component_id":"use-cases","captured_at":"1970-01-01T00:00:00.000Z"}}}
```

#### `node packages/cli/dist/index.js init --repo '/tmp/uc-tiers-acceptance/workspace' --template generic --component tiers --json`

```text
exit=0
{"schema_version":1,"protocol_version":1,"command":"init","ok":true,"complete":true,"data":{"schema_version":1,"status":"created","template":"generic","component_id":"tiers","default_verifier":{"id":"acceptance","kind":"script","command":["false","TODO-replace-with-your-verifier-command-for-{slug}"]},"created_files":["use-cases.yml","use-cases/example.yml"],"next_steps":["Edit use-cases/example.yml — replace the example row with a real use case.","Run `uc matrix validate --repo . --json` to confirm the matrix is clean.","Bind the implementing code with `uc bind` — code-marker grammar in docs/markers-adoption.md.","Wire the `acceptance` verifier in use-cases.yml to your real test command (docs/cli.md).","Generate an ed25519 keypair — commit the PUBLIC key, keep the PRIVATE key in a CI secret only (docs/security.md).","Let trusted CI mint FRESH proofs with `uc prove` (docs/cli.md, docs/security.md)."],"diagnostics":[]},"diagnostics":[],"context":{"workspace_root":"/tmp/uc-tiers-acceptance/workspace","data_root":"/tmp/uc-tiers-acceptance/workspace","component_id":"tiers","workspace_snapshot":{"repository_id":"unknown","vcs":"unknown","head_revision":"unknown","dirty":false,"working_tree_digest":"sha256:0000000000000000000000000000000000000000000000000000000000000000","component_id":"tiers","captured_at":"1970-01-01T00:00:00.000Z"}}}
```

#### `node packages/cli/dist/index.js matrix validate --repo '/tmp/uc-tiers-acceptance/workspace' --json`

```text
exit=0
{"schema_version":1,"protocol_version":1,"command":"matrix.validate","ok":true,"complete":true,"data":{"schema_version":1,"complete":true,"valid":true,"integrity":{"state":"clean","populated":true,"blocking_diagnostic_count":0},"files":[{"path":"use-cases/example.yml","status":"loaded","semantic_hash":"sha256:9d3540c8a771803bfba3f197229c9118e0bdacc9844dc6a40afdecd5ffccab07","file_hash":"sha256:43158ceac8c6614dbd7fecbadb7d8429a2ca258d4e934647c49d8b309315cfa9"}],"counts":{"files_discovered":1,"files_loaded":1,"files_excluded":0,"use_case_candidates":1,"use_cases_addressable":1,"use_cases_ambiguous":0,"use_cases_structurally_clean":1,"broken_references":0},"ambiguous_ids":[]},"diagnostics":[],"context":{"workspace_root":"/private/tmp/uc-tiers-acceptance/workspace","data_root":"/private/tmp/uc-tiers-acceptance/workspace","component_id":"tiers","workspace_snapshot":{"repository_id":"unknown","vcs":"unknown","head_revision":"unknown","dirty":false,"working_tree_digest":"sha256:0000000000000000000000000000000000000000000000000000000000000000","component_id":"tiers","captured_at":"1970-01-01T00:00:00.000Z"}}}
```

## Valid Baselines

### Ed25519 trusted-host token approval

Command: `node packages/cli/dist/index.js approve-run --request '/tmp/uc-tiers-acceptance/outputs/baseline_valid_ed25519.request.json' --key-file '/tmp/uc-tiers-acceptance/keys/trusted/ci-signing-key.pem' --key-id 'trusted-host' --decision 'approved' --out '/tmp/uc-tiers-acceptance/outputs/baseline_valid_ed25519.token.json' --json`

```text
exit=0
{"schema_version":1,"protocol_version":1,"command":"showcase.approve_run","ok":true,"complete":true,"data":{"approval_token_path":"/tmp/uc-tiers-acceptance/outputs/baseline_valid_ed25519.token.json","jti":"approval.01ebafab-11eb-40b2-b2b9-53faff4099d0","decision":"approved","key_id":"trusted-host","assurance_method":"os_presence","assurance_tier":"trusted_host_user_presence"},"diagnostics":[],"context":{"workspace_root":"/Users/admin/repos/use-case-matrix-g2-attack","data_root":"/Users/admin/repos/use-case-matrix-g2-attack","component_id":"use-cases","workspace_snapshot":{"repository_id":"unknown","vcs":"unknown","head_revision":"unknown","dirty":false,"working_tree_digest":"sha256:0000000000000000000000000000000000000000000000000000000000000000","component_id":"use-cases","captured_at":"1970-01-01T00:00:00.000Z"}}}
```

Command: `node packages/cli/dist/index.js showcase approve --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_baseline_valid_ed25519' --statement 'Attack baseline_valid_ed25519' --approval-token '/tmp/uc-tiers-acceptance/outputs/baseline_valid_ed25519.token.json' --idempotency-key 'approve-baseline_valid_ed25519' --json`

```text
exit=0
{"schema_version":1,"protocol_version":1,"command":"showcase.approve","ok":true,"complete":true,"data":{"schema_version":1,"run_id":"run.start_baseline_valid_ed25519","appended_event_ids":["evt.run.start_baseline_valid_ed25519.6"],"event":{"schema_version":1,"event_type":"approval_recorded","event_id":"evt.run.start_baseline_valid_ed25519.6","run_id":"run.start_baseline_valid_ed25519","aggregate_id":"run.start_baseline_valid_ed25519","sequence":6,"recorded_at":"2026-06-25T12:04:00.000Z","actor_type":"user","host_surface":"codex.cli","idempotency_key":"approve-baseline_valid_ed25519","intent_digest":"sha256:fe37b80de78a539fc063fa1c31fafd892a0ea867eaac21f8ca8f5b74b62f686b","payload":{"decision":"approved","approver":{"type":"user","actor_type":"user","assurance_tier":"trusted_host_user_presence"},"capture_method":"host_signed_approval_token","approval_statement":"Attack baseline_valid_ed25519","scope":{"plan_content_hash":"sha256:52d3017a0d68671b787df4cc924d0c1e4629462488b51fa65ad29f6c8fb7241b","finish_event_id":"evt.run.start_baseline_valid_ed25519.4","run_outcome":"passed","known_gap_count":0},"approval_token":{"approval_token_schema":"ucase-approval-token-v1","binding":{"run_id":"run.start_baseline_valid_ed25519","finish_event_id":"evt.run.start_baseline_valid_ed25519.4","plan_content_hash":"sha256:52d3017a0d68671b787df4cc924d0c1e4629462488b51fa65ad29f6c8fb7241b","ledger_head_hash":"sha256:88c17665d0a903afee71cd03d06be61be27839200af8df2c162f3069ed39fc7c","evidence_digest":"sha256:17ac495f58e9e23a5614c7aaa650fa74c063a9716a774afa25c43f88d6addcd5","git_commit":"unknown","ci_freshness_digest":"sha256:b97cb207a1d9073623e3777dc158f51eba2f4b3f0b02d35f69fdf54151516e85"},"jti":"approval.01ebafab-11eb-40b2-b2b9-53faff4099d0","iat":"2026-07-05T11:30:52.495Z","exp":"2026-07-05T11:45:52.495Z","created_at":"2026-07-05T11:30:52.495Z","decision":"approved","assurance_method":"os_presence","assurance_tier":"trusted_host_user_presence","signature":{"alg":"ed25519","key_id":"trusted-host","value":"xhPry6uEDoHLFe5lT0ZEXrTvdTI1E6kfD5i+rqq/Yf+ftchLeizbJLy+/kwrzpUZO8uaJuXGrgeUcij9sSsuAA=="}}}},"status":{"schema_version":1,"run_id":"run.start_baseline_valid_ed25519","complete":true,"execution_status":"completed","run_outcome":"passed","approval_state":"approved","unresolved_failure_count":0,"approval":{"actor_type":"user","assurance_tier":"trusted_host_user_presence"},"items":[{"plan_item_id":"item.tiers.approval.happy_path","verdict":"pass","item_currency":"current","verification_state":"requirements_met","latest_observation_event_id":"evt.run.start_baseline_valid_ed25519.2","latest_verdict_event_id":"evt.run.start_baseline_valid_ed25519.3"}],"known_gaps":[],"diagnostic_summary":{}}},"diagnostics":[],"context":{"workspace_root":"/private/tmp/uc-tiers-acceptance/workspace","data_root":"/private/tmp/uc-tiers-acceptance/workspace","component_id":"tiers","workspace_snapshot":{"repository_id":"unknown","vcs":"unknown","head_revision":"unknown","dirty":false,"working_tree_digest":"sha256:0000000000000000000000000000000000000000000000000000000000000000","component_id":"tiers","captured_at":"1970-01-01T00:00:00.000Z"}}}
```

### WebAuthn hardware token approval

Command: `node packages/cli/dist/index.js approve-run --request '/tmp/uc-tiers-acceptance/outputs/baseline_valid_webauthn.request.json' --webauthn-assertion '/tmp/uc-tiers-acceptance/outputs/baseline_valid_webauthn.assertion.json' --decision 'approved' --out '/tmp/uc-tiers-acceptance/outputs/baseline_valid_webauthn.token.json' --json`

```text
exit=0
{"schema_version":1,"protocol_version":1,"command":"showcase.approve_run","ok":true,"complete":true,"data":{"approval_token_path":"/tmp/uc-tiers-acceptance/outputs/baseline_valid_webauthn.token.json","jti":"approval.a38d0877-9c54-4ffc-ae13-26244d359a70","decision":"approved","credential_id":"webauthn-trusted","assurance_method":"webauthn","assurance_tier":"webauthn_hardware"},"diagnostics":[],"context":{"workspace_root":"/Users/admin/repos/use-case-matrix-g2-attack","data_root":"/Users/admin/repos/use-case-matrix-g2-attack","component_id":"use-cases","workspace_snapshot":{"repository_id":"unknown","vcs":"unknown","head_revision":"unknown","dirty":false,"working_tree_digest":"sha256:0000000000000000000000000000000000000000000000000000000000000000","component_id":"use-cases","captured_at":"1970-01-01T00:00:00.000Z"}}}
```

Command: `node packages/cli/dist/index.js showcase approve --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_baseline_valid_webauthn' --statement 'Attack baseline_valid_webauthn' --approval-token '/tmp/uc-tiers-acceptance/outputs/baseline_valid_webauthn.token.json' --idempotency-key 'approve-baseline_valid_webauthn' --json`

```text
exit=0
{"schema_version":1,"protocol_version":1,"command":"showcase.approve","ok":true,"complete":true,"data":{"schema_version":1,"run_id":"run.start_baseline_valid_webauthn","appended_event_ids":["evt.run.start_baseline_valid_webauthn.6"],"event":{"schema_version":1,"event_type":"approval_recorded","event_id":"evt.run.start_baseline_valid_webauthn.6","run_id":"run.start_baseline_valid_webauthn","aggregate_id":"run.start_baseline_valid_webauthn","sequence":6,"recorded_at":"2026-06-25T12:04:00.000Z","actor_type":"user","host_surface":"codex.cli","idempotency_key":"approve-baseline_valid_webauthn","intent_digest":"sha256:b1f1c9d59ff16a7c4f15b8b09aafa0abcaed7eaa143714d2ea6df5fd434670e8","payload":{"decision":"approved","approver":{"type":"user","actor_type":"user","assurance_tier":"webauthn_hardware"},"capture_method":"host_signed_approval_token","approval_statement":"Attack baseline_valid_webauthn","scope":{"plan_content_hash":"sha256:52d3017a0d68671b787df4cc924d0c1e4629462488b51fa65ad29f6c8fb7241b","finish_event_id":"evt.run.start_baseline_valid_webauthn.4","run_outcome":"passed","known_gap_count":0},"approval_token":{"approval_token_schema":"ucase-approval-token-v1","binding":{"run_id":"run.start_baseline_valid_webauthn","finish_event_id":"evt.run.start_baseline_valid_webauthn.4","plan_content_hash":"sha256:52d3017a0d68671b787df4cc924d0c1e4629462488b51fa65ad29f6c8fb7241b","ledger_head_hash":"sha256:34d366f1b94cbbda9cf9e5e72fa595b34125563f509bcfcbadbd11ee240031db","evidence_digest":"sha256:d3b85b9daba245e137e9fe0eb943a3073507260fcff894b5ece7edf89d1b7066","git_commit":"unknown","ci_freshness_digest":"sha256:bcde02657020dafc97d754cfa01e763e3c645c101658e53b87c4efc4efadb96e"},"jti":"approval.a38d0877-9c54-4ffc-ae13-26244d359a70","iat":"2026-07-05T11:30:55.719Z","exp":"2026-07-05T11:45:55.719Z","created_at":"2026-07-05T11:30:55.719Z","decision":"approved","assurance_method":"webauthn","assurance_tier":"webauthn_hardware","signature":{"alg":"webauthn","credential_id":"webauthn-trusted","authenticator_data":"YeoBkac-amCeXF6gLCC-rYF8_aZm4dJPvqr6tImT46kFAAAAAQ","client_data_json":"eyJ0eXBlIjoid2ViYXV0aG4uZ2V0IiwiY2hhbGxlbmdlIjoia0dTcEJSUDl5WnNQOUlxd3VpU0FiS2NnSDRlMnhDVDd0dUdYUFdlUkVrOCIsIm9yaWdpbiI6Imh0dHBzOi8vdXNlLWNhc2VzLmRldiJ9","signature":"FVmFyYHBPkT63QZ5GswNY0hxZJwHlRwA0MPn4VnSYMKfjqOsfE5Wr-q50kDBBi1U6DegM6D0bjpz1GMVBN1zDA"}}}},"status":{"schema_version":1,"run_id":"run.start_baseline_valid_webauthn","complete":true,"execution_status":"completed","run_outcome":"passed","approval_state":"approved","unresolved_failure_count":0,"approval":{"actor_type":"user","assurance_tier":"webauthn_hardware"},"items":[{"plan_item_id":"item.tiers.approval.happy_path","verdict":"pass","item_currency":"current","verification_state":"requirements_met","latest_observation_event_id":"evt.run.start_baseline_valid_webauthn.2","latest_verdict_event_id":"evt.run.start_baseline_valid_webauthn.3"}],"known_gaps":[],"diagnostic_summary":{}}},"diagnostics":[],"context":{"workspace_root":"/private/tmp/uc-tiers-acceptance/workspace","data_root":"/private/tmp/uc-tiers-acceptance/workspace","component_id":"tiers","workspace_snapshot":{"repository_id":"unknown","vcs":"unknown","head_revision":"unknown","dirty":false,"working_tree_digest":"sha256:0000000000000000000000000000000000000000000000000000000000000000","component_id":"tiers","captured_at":"1970-01-01T00:00:00.000Z"}}}
```

## Attack Results

### PASS - B1a_no_token: B1 no token

Attack: Try to approve a user-required run as user with no approval token.

Expected: Rejected/fail-closed: trusted user confirmation required; approval stays pending.

Prep commands:

- `node packages/cli/dist/index.js showcase start --repo '/tmp/uc-tiers-acceptance/workspace' --adhoc --select 'tiers.approval.happy_path' --idempotency-key 'start-B1a_no_token' --json`
- `node packages/cli/dist/index.js showcase record-observation --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_b1a_no_token' --item 'item.tiers.approval.happy_path' --text 'Observation for B1a_no_token: behavior matched.' --idempotency-key 'observe-B1a_no_token' --json`
- `node packages/cli/dist/index.js showcase record-verdict --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_b1a_no_token' --item 'item.tiers.approval.happy_path' --verdict pass --idempotency-key 'verdict-B1a_no_token' --json`
- `node packages/cli/dist/index.js showcase finish --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_b1a_no_token' --idempotency-key 'finish-B1a_no_token' --json`

Attack command: `node packages/cli/dist/index.js showcase approve --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_b1a_no_token' --statement 'Attack B1a_no_token' --actor user --idempotency-key 'approve-B1a_no_token' --json`

Actual output:

```text
exit=1
{"schema_version":1,"protocol_version":1,"command":"showcase.approve","ok":false,"complete":false,"data":{},"diagnostics":[{"code":"showcase.trusted_user_confirmation_required","severity":"error","message":"User approval requires a signed host approval token (out-of-band human sign-off).","source_path":null,"json_pointer":null,"entity_id":null,"related_ids":[]}],"context":{"workspace_root":"/Users/admin/repos/use-case-matrix-g2-attack","data_root":"/Users/admin/repos/use-case-matrix-g2-attack","component_id":"use-cases","workspace_snapshot":{"repository_id":"unknown","vcs":"unknown","head_revision":"unknown","dirty":false,"working_tree_digest":"sha256:0000000000000000000000000000000000000000000000000000000000000000","component_id":"use-cases","captured_at":"1970-01-01T00:00:00.000Z"}}}
```

Verdict: PASS - attack was blocked/fail-closed.

### PASS - B1b_empty_token: B1 empty token file

Attack: Pass an empty approval-token file.

Expected: Rejected/fail-closed: token unreadable.

Prep commands:

- `node packages/cli/dist/index.js showcase start --repo '/tmp/uc-tiers-acceptance/workspace' --adhoc --select 'tiers.approval.happy_path' --idempotency-key 'start-B1b_empty_token' --json`
- `node packages/cli/dist/index.js showcase record-observation --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_b1b_empty_token' --item 'item.tiers.approval.happy_path' --text 'Observation for B1b_empty_token: behavior matched.' --idempotency-key 'observe-B1b_empty_token' --json`
- `node packages/cli/dist/index.js showcase record-verdict --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_b1b_empty_token' --item 'item.tiers.approval.happy_path' --verdict pass --idempotency-key 'verdict-B1b_empty_token' --json`
- `node packages/cli/dist/index.js showcase finish --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_b1b_empty_token' --idempotency-key 'finish-B1b_empty_token' --json`

Attack command: `node packages/cli/dist/index.js showcase approve --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_b1b_empty_token' --statement 'Attack B1b_empty_token' --approval-token '/tmp/uc-tiers-acceptance/outputs/B1b_empty_token.empty.json' --idempotency-key 'approve-B1b_empty_token' --json`

Actual output:

```text
exit=1
{"schema_version":1,"protocol_version":1,"command":"showcase.approve","ok":false,"complete":false,"data":{},"diagnostics":[{"code":"showcase.approval_token_unreadable","severity":"error","message":"could not read/parse --approval-token: Unexpected end of JSON input","source_path":null,"json_pointer":null,"entity_id":null,"related_ids":[]}],"context":{"workspace_root":"/Users/admin/repos/use-case-matrix-g2-attack","data_root":"/Users/admin/repos/use-case-matrix-g2-attack","component_id":"use-cases","workspace_snapshot":{"repository_id":"unknown","vcs":"unknown","head_revision":"unknown","dirty":false,"working_tree_digest":"sha256:0000000000000000000000000000000000000000000000000000000000000000","component_id":"use-cases","captured_at":"1970-01-01T00:00:00.000Z"}}}
```

Verdict: PASS - attack was blocked/fail-closed.

### PASS - B2_forged_unsigned: B2 forged unsigned token

Attack: Create a token-shaped object from a real request but omit signature.

Expected: Rejected/fail-closed: SIGNATURE_MISSING.

Prep commands:

- `node packages/cli/dist/index.js showcase start --repo '/tmp/uc-tiers-acceptance/workspace' --adhoc --select 'tiers.approval.happy_path' --idempotency-key 'start-B2_forged_unsigned' --json`
- `node packages/cli/dist/index.js showcase record-observation --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_b2_forged_unsigned' --item 'item.tiers.approval.happy_path' --text 'Observation for B2_forged_unsigned: behavior matched.' --idempotency-key 'observe-B2_forged_unsigned' --json`
- `node packages/cli/dist/index.js showcase record-verdict --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_b2_forged_unsigned' --item 'item.tiers.approval.happy_path' --verdict pass --idempotency-key 'verdict-B2_forged_unsigned' --json`
- `node packages/cli/dist/index.js showcase finish --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_b2_forged_unsigned' --idempotency-key 'finish-B2_forged_unsigned' --json`
- `node packages/cli/dist/index.js showcase request-approval --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_b2_forged_unsigned' --json > '/tmp/uc-tiers-acceptance/outputs/B2_forged_unsigned.request.json'`

Attack command: `node packages/cli/dist/index.js showcase approve --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_b2_forged_unsigned' --statement 'Attack B2_forged_unsigned' --approval-token '/tmp/uc-tiers-acceptance/outputs/B2_forged_unsigned.unsigned-token.json' --idempotency-key 'approve-B2_forged_unsigned' --json`

Actual output:

```text
exit=1
{"schema_version":1,"protocol_version":1,"command":"showcase.approve","ok":false,"complete":false,"data":{},"diagnostics":[{"code":"showcase.trusted_user_confirmation_required","severity":"error","message":"User approval token rejected: SIGNATURE_MISSING (proof event has no usable signature block (unsigned events are invalid))","source_path":null,"json_pointer":null,"entity_id":null,"related_ids":[]}],"context":{"workspace_root":"/Users/admin/repos/use-case-matrix-g2-attack","data_root":"/Users/admin/repos/use-case-matrix-g2-attack","component_id":"use-cases","workspace_snapshot":{"repository_id":"unknown","vcs":"unknown","head_revision":"unknown","dirty":false,"working_tree_digest":"sha256:0000000000000000000000000000000000000000000000000000000000000000","component_id":"use-cases","captured_at":"1970-01-01T00:00:00.000Z"}}}
```

Verdict: PASS - attack was blocked/fail-closed.

### PASS - B3_wrong_key: B3 wrong key

Attack: Sign with the wrong private key while claiming the pinned trusted-host key id.

Expected: Rejected/fail-closed: BAD_SIGNATURE.

Prep commands:

- `node packages/cli/dist/index.js showcase start --repo '/tmp/uc-tiers-acceptance/workspace' --adhoc --select 'tiers.approval.happy_path' --idempotency-key 'start-B3_wrong_key' --json`
- `node packages/cli/dist/index.js showcase record-observation --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_b3_wrong_key' --item 'item.tiers.approval.happy_path' --text 'Observation for B3_wrong_key: behavior matched.' --idempotency-key 'observe-B3_wrong_key' --json`
- `node packages/cli/dist/index.js showcase record-verdict --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_b3_wrong_key' --item 'item.tiers.approval.happy_path' --verdict pass --idempotency-key 'verdict-B3_wrong_key' --json`
- `node packages/cli/dist/index.js showcase finish --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_b3_wrong_key' --idempotency-key 'finish-B3_wrong_key' --json`
- `node packages/cli/dist/index.js showcase request-approval --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_b3_wrong_key' --json > '/tmp/uc-tiers-acceptance/outputs/B3_wrong_key.request.json'`
- `node packages/cli/dist/index.js approve-run --request '/tmp/uc-tiers-acceptance/outputs/B3_wrong_key.request.json' --key-file '/tmp/uc-tiers-acceptance/keys/wrong/ci-signing-key.pem' --key-id 'trusted-host' --decision 'approved' --out '/tmp/uc-tiers-acceptance/outputs/B3_wrong_key.token.json' --json`

Attack command: `node packages/cli/dist/index.js showcase approve --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_b3_wrong_key' --statement 'Attack B3_wrong_key' --approval-token '/tmp/uc-tiers-acceptance/outputs/B3_wrong_key.token.json' --idempotency-key 'approve-B3_wrong_key' --json`

Actual output:

```text
exit=1
{"schema_version":1,"protocol_version":1,"command":"showcase.approve","ok":false,"complete":false,"data":{},"diagnostics":[{"code":"showcase.trusted_user_confirmation_required","severity":"error","message":"User approval token rejected: BAD_SIGNATURE (signature for key_id trusted-host did not verify)","source_path":null,"json_pointer":null,"entity_id":null,"related_ids":[]}],"context":{"workspace_root":"/Users/admin/repos/use-case-matrix-g2-attack","data_root":"/Users/admin/repos/use-case-matrix-g2-attack","component_id":"use-cases","workspace_snapshot":{"repository_id":"unknown","vcs":"unknown","head_revision":"unknown","dirty":false,"working_tree_digest":"sha256:0000000000000000000000000000000000000000000000000000000000000000","component_id":"use-cases","captured_at":"1970-01-01T00:00:00.000Z"}}}
```

Verdict: PASS - attack was blocked/fail-closed.

### PASS - B4_binding_run_id: B4 tampered binding.run_id

Attack: Sign a valid token over a request whose binding.run_id does not match the live run.

Expected: Rejected/fail-closed: BINDING_MISMATCH.

Prep commands:

- `node packages/cli/dist/index.js showcase start --repo '/tmp/uc-tiers-acceptance/workspace' --adhoc --select 'tiers.approval.happy_path' --idempotency-key 'start-B4_binding_run_id' --json`
- `node packages/cli/dist/index.js showcase record-observation --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_b4_binding_run_id' --item 'item.tiers.approval.happy_path' --text 'Observation for B4_binding_run_id: behavior matched.' --idempotency-key 'observe-B4_binding_run_id' --json`
- `node packages/cli/dist/index.js showcase record-verdict --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_b4_binding_run_id' --item 'item.tiers.approval.happy_path' --verdict pass --idempotency-key 'verdict-B4_binding_run_id' --json`
- `node packages/cli/dist/index.js showcase finish --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_b4_binding_run_id' --idempotency-key 'finish-B4_binding_run_id' --json`
- `node packages/cli/dist/index.js showcase request-approval --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_b4_binding_run_id' --json > '/tmp/uc-tiers-acceptance/outputs/B4_binding_run_id.request.json'`
- `node packages/cli/dist/index.js approve-run --request '/tmp/uc-tiers-acceptance/outputs/B4_binding_run_id.bad-request.json' --key-file '/tmp/uc-tiers-acceptance/keys/trusted/ci-signing-key.pem' --key-id 'trusted-host' --decision 'approved' --out '/tmp/uc-tiers-acceptance/outputs/B4_binding_run_id.token.json' --json`

Attack command: `node packages/cli/dist/index.js showcase approve --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_b4_binding_run_id' --statement 'Attack B4_binding_run_id' --approval-token '/tmp/uc-tiers-acceptance/outputs/B4_binding_run_id.token.json' --idempotency-key 'approve-B4_binding_run_id' --json`

Actual output:

```text
exit=1
{"schema_version":1,"protocol_version":1,"command":"showcase.approve","ok":false,"complete":false,"data":{},"diagnostics":[{"code":"showcase.approval_binding_mismatch","severity":"error","message":"User approval token rejected: BINDING_MISMATCH (approval token binding.run_id does not match the live run)","source_path":null,"json_pointer":null,"entity_id":null,"related_ids":[]}],"context":{"workspace_root":"/Users/admin/repos/use-case-matrix-g2-attack","data_root":"/Users/admin/repos/use-case-matrix-g2-attack","component_id":"use-cases","workspace_snapshot":{"repository_id":"unknown","vcs":"unknown","head_revision":"unknown","dirty":false,"working_tree_digest":"sha256:0000000000000000000000000000000000000000000000000000000000000000","component_id":"use-cases","captured_at":"1970-01-01T00:00:00.000Z"}}}
```

Verdict: PASS - attack was blocked/fail-closed.

### PASS - B4_binding_finish_event_id: B4 tampered binding.finish_event_id

Attack: Sign a valid token over a request whose binding.finish_event_id does not match the live run.

Expected: Rejected/fail-closed: BINDING_MISMATCH.

Prep commands:

- `node packages/cli/dist/index.js showcase start --repo '/tmp/uc-tiers-acceptance/workspace' --adhoc --select 'tiers.approval.happy_path' --idempotency-key 'start-B4_binding_finish_event_id' --json`
- `node packages/cli/dist/index.js showcase record-observation --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_b4_binding_finish_event_id' --item 'item.tiers.approval.happy_path' --text 'Observation for B4_binding_finish_event_id: behavior matched.' --idempotency-key 'observe-B4_binding_finish_event_id' --json`
- `node packages/cli/dist/index.js showcase record-verdict --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_b4_binding_finish_event_id' --item 'item.tiers.approval.happy_path' --verdict pass --idempotency-key 'verdict-B4_binding_finish_event_id' --json`
- `node packages/cli/dist/index.js showcase finish --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_b4_binding_finish_event_id' --idempotency-key 'finish-B4_binding_finish_event_id' --json`
- `node packages/cli/dist/index.js showcase request-approval --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_b4_binding_finish_event_id' --json > '/tmp/uc-tiers-acceptance/outputs/B4_binding_finish_event_id.request.json'`
- `node packages/cli/dist/index.js approve-run --request '/tmp/uc-tiers-acceptance/outputs/B4_binding_finish_event_id.bad-request.json' --key-file '/tmp/uc-tiers-acceptance/keys/trusted/ci-signing-key.pem' --key-id 'trusted-host' --decision 'approved' --out '/tmp/uc-tiers-acceptance/outputs/B4_binding_finish_event_id.token.json' --json`

Attack command: `node packages/cli/dist/index.js showcase approve --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_b4_binding_finish_event_id' --statement 'Attack B4_binding_finish_event_id' --approval-token '/tmp/uc-tiers-acceptance/outputs/B4_binding_finish_event_id.token.json' --idempotency-key 'approve-B4_binding_finish_event_id' --json`

Actual output:

```text
exit=1
{"schema_version":1,"protocol_version":1,"command":"showcase.approve","ok":false,"complete":false,"data":{},"diagnostics":[{"code":"showcase.approval_binding_mismatch","severity":"error","message":"User approval token rejected: BINDING_MISMATCH (approval token binding.finish_event_id does not match the live run)","source_path":null,"json_pointer":null,"entity_id":null,"related_ids":[]}],"context":{"workspace_root":"/Users/admin/repos/use-case-matrix-g2-attack","data_root":"/Users/admin/repos/use-case-matrix-g2-attack","component_id":"use-cases","workspace_snapshot":{"repository_id":"unknown","vcs":"unknown","head_revision":"unknown","dirty":false,"working_tree_digest":"sha256:0000000000000000000000000000000000000000000000000000000000000000","component_id":"use-cases","captured_at":"1970-01-01T00:00:00.000Z"}}}
```

Verdict: PASS - attack was blocked/fail-closed.

### PASS - B4_binding_plan_content_hash: B4 tampered binding.plan_content_hash

Attack: Sign a valid token over a request whose binding.plan_content_hash does not match the live run.

Expected: Rejected/fail-closed: BINDING_MISMATCH.

Prep commands:

- `node packages/cli/dist/index.js showcase start --repo '/tmp/uc-tiers-acceptance/workspace' --adhoc --select 'tiers.approval.happy_path' --idempotency-key 'start-B4_binding_plan_content_hash' --json`
- `node packages/cli/dist/index.js showcase record-observation --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_b4_binding_plan_content_hash' --item 'item.tiers.approval.happy_path' --text 'Observation for B4_binding_plan_content_hash: behavior matched.' --idempotency-key 'observe-B4_binding_plan_content_hash' --json`
- `node packages/cli/dist/index.js showcase record-verdict --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_b4_binding_plan_content_hash' --item 'item.tiers.approval.happy_path' --verdict pass --idempotency-key 'verdict-B4_binding_plan_content_hash' --json`
- `node packages/cli/dist/index.js showcase finish --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_b4_binding_plan_content_hash' --idempotency-key 'finish-B4_binding_plan_content_hash' --json`
- `node packages/cli/dist/index.js showcase request-approval --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_b4_binding_plan_content_hash' --json > '/tmp/uc-tiers-acceptance/outputs/B4_binding_plan_content_hash.request.json'`
- `node packages/cli/dist/index.js approve-run --request '/tmp/uc-tiers-acceptance/outputs/B4_binding_plan_content_hash.bad-request.json' --key-file '/tmp/uc-tiers-acceptance/keys/trusted/ci-signing-key.pem' --key-id 'trusted-host' --decision 'approved' --out '/tmp/uc-tiers-acceptance/outputs/B4_binding_plan_content_hash.token.json' --json`

Attack command: `node packages/cli/dist/index.js showcase approve --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_b4_binding_plan_content_hash' --statement 'Attack B4_binding_plan_content_hash' --approval-token '/tmp/uc-tiers-acceptance/outputs/B4_binding_plan_content_hash.token.json' --idempotency-key 'approve-B4_binding_plan_content_hash' --json`

Actual output:

```text
exit=1
{"schema_version":1,"protocol_version":1,"command":"showcase.approve","ok":false,"complete":false,"data":{},"diagnostics":[{"code":"showcase.approval_binding_mismatch","severity":"error","message":"User approval token rejected: BINDING_MISMATCH (approval token binding.plan_content_hash does not match the live run)","source_path":null,"json_pointer":null,"entity_id":null,"related_ids":[]}],"context":{"workspace_root":"/Users/admin/repos/use-case-matrix-g2-attack","data_root":"/Users/admin/repos/use-case-matrix-g2-attack","component_id":"use-cases","workspace_snapshot":{"repository_id":"unknown","vcs":"unknown","head_revision":"unknown","dirty":false,"working_tree_digest":"sha256:0000000000000000000000000000000000000000000000000000000000000000","component_id":"use-cases","captured_at":"1970-01-01T00:00:00.000Z"}}}
```

Verdict: PASS - attack was blocked/fail-closed.

### PASS - B4_binding_ledger_head_hash: B4 tampered binding.ledger_head_hash

Attack: Sign a valid token over a request whose binding.ledger_head_hash does not match the live run.

Expected: Rejected/fail-closed: BINDING_MISMATCH.

Prep commands:

- `node packages/cli/dist/index.js showcase start --repo '/tmp/uc-tiers-acceptance/workspace' --adhoc --select 'tiers.approval.happy_path' --idempotency-key 'start-B4_binding_ledger_head_hash' --json`
- `node packages/cli/dist/index.js showcase record-observation --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_b4_binding_ledger_head_hash' --item 'item.tiers.approval.happy_path' --text 'Observation for B4_binding_ledger_head_hash: behavior matched.' --idempotency-key 'observe-B4_binding_ledger_head_hash' --json`
- `node packages/cli/dist/index.js showcase record-verdict --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_b4_binding_ledger_head_hash' --item 'item.tiers.approval.happy_path' --verdict pass --idempotency-key 'verdict-B4_binding_ledger_head_hash' --json`
- `node packages/cli/dist/index.js showcase finish --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_b4_binding_ledger_head_hash' --idempotency-key 'finish-B4_binding_ledger_head_hash' --json`
- `node packages/cli/dist/index.js showcase request-approval --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_b4_binding_ledger_head_hash' --json > '/tmp/uc-tiers-acceptance/outputs/B4_binding_ledger_head_hash.request.json'`
- `node packages/cli/dist/index.js approve-run --request '/tmp/uc-tiers-acceptance/outputs/B4_binding_ledger_head_hash.bad-request.json' --key-file '/tmp/uc-tiers-acceptance/keys/trusted/ci-signing-key.pem' --key-id 'trusted-host' --decision 'approved' --out '/tmp/uc-tiers-acceptance/outputs/B4_binding_ledger_head_hash.token.json' --json`

Attack command: `node packages/cli/dist/index.js showcase approve --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_b4_binding_ledger_head_hash' --statement 'Attack B4_binding_ledger_head_hash' --approval-token '/tmp/uc-tiers-acceptance/outputs/B4_binding_ledger_head_hash.token.json' --idempotency-key 'approve-B4_binding_ledger_head_hash' --json`

Actual output:

```text
exit=1
{"schema_version":1,"protocol_version":1,"command":"showcase.approve","ok":false,"complete":false,"data":{},"diagnostics":[{"code":"showcase.approval_binding_mismatch","severity":"error","message":"User approval token rejected: BINDING_MISMATCH (approval token binding.ledger_head_hash does not match the live run)","source_path":null,"json_pointer":null,"entity_id":null,"related_ids":[]}],"context":{"workspace_root":"/Users/admin/repos/use-case-matrix-g2-attack","data_root":"/Users/admin/repos/use-case-matrix-g2-attack","component_id":"use-cases","workspace_snapshot":{"repository_id":"unknown","vcs":"unknown","head_revision":"unknown","dirty":false,"working_tree_digest":"sha256:0000000000000000000000000000000000000000000000000000000000000000","component_id":"use-cases","captured_at":"1970-01-01T00:00:00.000Z"}}}
```

Verdict: PASS - attack was blocked/fail-closed.

### PASS - B4_binding_evidence_digest: B4 tampered binding.evidence_digest

Attack: Sign a valid token over a request whose binding.evidence_digest does not match the live run.

Expected: Rejected/fail-closed: BINDING_MISMATCH.

Prep commands:

- `node packages/cli/dist/index.js showcase start --repo '/tmp/uc-tiers-acceptance/workspace' --adhoc --select 'tiers.approval.happy_path' --idempotency-key 'start-B4_binding_evidence_digest' --json`
- `node packages/cli/dist/index.js showcase record-observation --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_b4_binding_evidence_digest' --item 'item.tiers.approval.happy_path' --text 'Observation for B4_binding_evidence_digest: behavior matched.' --idempotency-key 'observe-B4_binding_evidence_digest' --json`
- `node packages/cli/dist/index.js showcase record-verdict --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_b4_binding_evidence_digest' --item 'item.tiers.approval.happy_path' --verdict pass --idempotency-key 'verdict-B4_binding_evidence_digest' --json`
- `node packages/cli/dist/index.js showcase finish --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_b4_binding_evidence_digest' --idempotency-key 'finish-B4_binding_evidence_digest' --json`
- `node packages/cli/dist/index.js showcase request-approval --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_b4_binding_evidence_digest' --json > '/tmp/uc-tiers-acceptance/outputs/B4_binding_evidence_digest.request.json'`
- `node packages/cli/dist/index.js approve-run --request '/tmp/uc-tiers-acceptance/outputs/B4_binding_evidence_digest.bad-request.json' --key-file '/tmp/uc-tiers-acceptance/keys/trusted/ci-signing-key.pem' --key-id 'trusted-host' --decision 'approved' --out '/tmp/uc-tiers-acceptance/outputs/B4_binding_evidence_digest.token.json' --json`

Attack command: `node packages/cli/dist/index.js showcase approve --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_b4_binding_evidence_digest' --statement 'Attack B4_binding_evidence_digest' --approval-token '/tmp/uc-tiers-acceptance/outputs/B4_binding_evidence_digest.token.json' --idempotency-key 'approve-B4_binding_evidence_digest' --json`

Actual output:

```text
exit=1
{"schema_version":1,"protocol_version":1,"command":"showcase.approve","ok":false,"complete":false,"data":{},"diagnostics":[{"code":"showcase.approval_binding_mismatch","severity":"error","message":"User approval token rejected: BINDING_MISMATCH (approval token binding.evidence_digest does not match the live run)","source_path":null,"json_pointer":null,"entity_id":null,"related_ids":[]}],"context":{"workspace_root":"/Users/admin/repos/use-case-matrix-g2-attack","data_root":"/Users/admin/repos/use-case-matrix-g2-attack","component_id":"use-cases","workspace_snapshot":{"repository_id":"unknown","vcs":"unknown","head_revision":"unknown","dirty":false,"working_tree_digest":"sha256:0000000000000000000000000000000000000000000000000000000000000000","component_id":"use-cases","captured_at":"1970-01-01T00:00:00.000Z"}}}
```

Verdict: PASS - attack was blocked/fail-closed.

### PASS - B4_binding_git_commit: B4 tampered binding.git_commit

Attack: Sign a valid token over a request whose binding.git_commit does not match the live run.

Expected: Rejected/fail-closed: BINDING_MISMATCH.

Prep commands:

- `node packages/cli/dist/index.js showcase start --repo '/tmp/uc-tiers-acceptance/workspace' --adhoc --select 'tiers.approval.happy_path' --idempotency-key 'start-B4_binding_git_commit' --json`
- `node packages/cli/dist/index.js showcase record-observation --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_b4_binding_git_commit' --item 'item.tiers.approval.happy_path' --text 'Observation for B4_binding_git_commit: behavior matched.' --idempotency-key 'observe-B4_binding_git_commit' --json`
- `node packages/cli/dist/index.js showcase record-verdict --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_b4_binding_git_commit' --item 'item.tiers.approval.happy_path' --verdict pass --idempotency-key 'verdict-B4_binding_git_commit' --json`
- `node packages/cli/dist/index.js showcase finish --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_b4_binding_git_commit' --idempotency-key 'finish-B4_binding_git_commit' --json`
- `node packages/cli/dist/index.js showcase request-approval --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_b4_binding_git_commit' --json > '/tmp/uc-tiers-acceptance/outputs/B4_binding_git_commit.request.json'`
- `node packages/cli/dist/index.js approve-run --request '/tmp/uc-tiers-acceptance/outputs/B4_binding_git_commit.bad-request.json' --key-file '/tmp/uc-tiers-acceptance/keys/trusted/ci-signing-key.pem' --key-id 'trusted-host' --decision 'approved' --out '/tmp/uc-tiers-acceptance/outputs/B4_binding_git_commit.token.json' --json`

Attack command: `node packages/cli/dist/index.js showcase approve --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_b4_binding_git_commit' --statement 'Attack B4_binding_git_commit' --approval-token '/tmp/uc-tiers-acceptance/outputs/B4_binding_git_commit.token.json' --idempotency-key 'approve-B4_binding_git_commit' --json`

Actual output:

```text
exit=1
{"schema_version":1,"protocol_version":1,"command":"showcase.approve","ok":false,"complete":false,"data":{},"diagnostics":[{"code":"showcase.approval_binding_mismatch","severity":"error","message":"User approval token rejected: BINDING_MISMATCH (approval token binding.git_commit does not match the live run)","source_path":null,"json_pointer":null,"entity_id":null,"related_ids":[]}],"context":{"workspace_root":"/Users/admin/repos/use-case-matrix-g2-attack","data_root":"/Users/admin/repos/use-case-matrix-g2-attack","component_id":"use-cases","workspace_snapshot":{"repository_id":"unknown","vcs":"unknown","head_revision":"unknown","dirty":false,"working_tree_digest":"sha256:0000000000000000000000000000000000000000000000000000000000000000","component_id":"use-cases","captured_at":"1970-01-01T00:00:00.000Z"}}}
```

Verdict: PASS - attack was blocked/fail-closed.

### PASS - B4_binding_ci_freshness_digest: B4 tampered binding.ci_freshness_digest

Attack: Sign a valid token over a request whose binding.ci_freshness_digest does not match the live run.

Expected: Rejected/fail-closed: BINDING_MISMATCH.

Prep commands:

- `node packages/cli/dist/index.js showcase start --repo '/tmp/uc-tiers-acceptance/workspace' --adhoc --select 'tiers.approval.happy_path' --idempotency-key 'start-B4_binding_ci_freshness_digest' --json`
- `node packages/cli/dist/index.js showcase record-observation --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_b4_binding_ci_freshness_digest' --item 'item.tiers.approval.happy_path' --text 'Observation for B4_binding_ci_freshness_digest: behavior matched.' --idempotency-key 'observe-B4_binding_ci_freshness_digest' --json`
- `node packages/cli/dist/index.js showcase record-verdict --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_b4_binding_ci_freshness_digest' --item 'item.tiers.approval.happy_path' --verdict pass --idempotency-key 'verdict-B4_binding_ci_freshness_digest' --json`
- `node packages/cli/dist/index.js showcase finish --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_b4_binding_ci_freshness_digest' --idempotency-key 'finish-B4_binding_ci_freshness_digest' --json`
- `node packages/cli/dist/index.js showcase request-approval --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_b4_binding_ci_freshness_digest' --json > '/tmp/uc-tiers-acceptance/outputs/B4_binding_ci_freshness_digest.request.json'`
- `node packages/cli/dist/index.js approve-run --request '/tmp/uc-tiers-acceptance/outputs/B4_binding_ci_freshness_digest.bad-request.json' --key-file '/tmp/uc-tiers-acceptance/keys/trusted/ci-signing-key.pem' --key-id 'trusted-host' --decision 'approved' --out '/tmp/uc-tiers-acceptance/outputs/B4_binding_ci_freshness_digest.token.json' --json`

Attack command: `node packages/cli/dist/index.js showcase approve --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_b4_binding_ci_freshness_digest' --statement 'Attack B4_binding_ci_freshness_digest' --approval-token '/tmp/uc-tiers-acceptance/outputs/B4_binding_ci_freshness_digest.token.json' --idempotency-key 'approve-B4_binding_ci_freshness_digest' --json`

Actual output:

```text
exit=1
{"schema_version":1,"protocol_version":1,"command":"showcase.approve","ok":false,"complete":false,"data":{},"diagnostics":[{"code":"showcase.approval_binding_mismatch","severity":"error","message":"User approval token rejected: BINDING_MISMATCH (approval token binding.ci_freshness_digest does not match the live run)","source_path":null,"json_pointer":null,"entity_id":null,"related_ids":[]}],"context":{"workspace_root":"/Users/admin/repos/use-case-matrix-g2-attack","data_root":"/Users/admin/repos/use-case-matrix-g2-attack","component_id":"use-cases","workspace_snapshot":{"repository_id":"unknown","vcs":"unknown","head_revision":"unknown","dirty":false,"working_tree_digest":"sha256:0000000000000000000000000000000000000000000000000000000000000000","component_id":"use-cases","captured_at":"1970-01-01T00:00:00.000Z"}}}
```

Verdict: PASS - attack was blocked/fail-closed.

### PASS - B5_expired: B5 expired token

Attack: Backdate request iat/exp within key validity but before current time, sign, and submit.

Expected: Rejected/fail-closed: TOKEN_EXPIRED.

Prep commands:

- `node packages/cli/dist/index.js showcase start --repo '/tmp/uc-tiers-acceptance/workspace' --adhoc --select 'tiers.approval.happy_path' --idempotency-key 'start-B5_expired' --json`
- `node packages/cli/dist/index.js showcase record-observation --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_b5_expired' --item 'item.tiers.approval.happy_path' --text 'Observation for B5_expired: behavior matched.' --idempotency-key 'observe-B5_expired' --json`
- `node packages/cli/dist/index.js showcase record-verdict --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_b5_expired' --item 'item.tiers.approval.happy_path' --verdict pass --idempotency-key 'verdict-B5_expired' --json`
- `node packages/cli/dist/index.js showcase finish --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_b5_expired' --idempotency-key 'finish-B5_expired' --json`
- `node packages/cli/dist/index.js showcase request-approval --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_b5_expired' --json > '/tmp/uc-tiers-acceptance/outputs/B5_expired.request.json'`
- `node packages/cli/dist/index.js approve-run --request '/tmp/uc-tiers-acceptance/outputs/B5_expired.expired-request.json' --key-file '/tmp/uc-tiers-acceptance/keys/trusted/ci-signing-key.pem' --key-id 'trusted-host' --decision 'approved' --out '/tmp/uc-tiers-acceptance/outputs/B5_expired.token.json' --json`

Attack command: `node packages/cli/dist/index.js showcase approve --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_b5_expired' --statement 'Attack B5_expired' --approval-token '/tmp/uc-tiers-acceptance/outputs/B5_expired.token.json' --idempotency-key 'approve-B5_expired' --json`

Actual output:

```text
exit=1
{"schema_version":1,"protocol_version":1,"command":"showcase.approve","ok":false,"complete":false,"data":{},"diagnostics":[{"code":"showcase.approval_token_expired","severity":"error","message":"User approval token rejected: TOKEN_EXPIRED (approval token has expired)","source_path":null,"json_pointer":null,"entity_id":null,"related_ids":[]}],"context":{"workspace_root":"/Users/admin/repos/use-case-matrix-g2-attack","data_root":"/Users/admin/repos/use-case-matrix-g2-attack","component_id":"use-cases","workspace_snapshot":{"repository_id":"unknown","vcs":"unknown","head_revision":"unknown","dirty":false,"working_tree_digest":"sha256:0000000000000000000000000000000000000000000000000000000000000000","component_id":"use-cases","captured_at":"1970-01-01T00:00:00.000Z"}}}
```

Verdict: PASS - attack was blocked/fail-closed.

### PASS - B6_replay_nonce: B6 replay / nonce burn

Attack: Approve once with a valid token, then submit the same token again.

Expected: Rejected/fail-closed: NONCE_BURNED.

Prep commands:

- `node packages/cli/dist/index.js showcase start --repo '/tmp/uc-tiers-acceptance/workspace' --adhoc --select 'tiers.approval.happy_path' --idempotency-key 'start-B6_replay_nonce' --json`
- `node packages/cli/dist/index.js showcase record-observation --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_b6_replay_nonce' --item 'item.tiers.approval.happy_path' --text 'Observation for B6_replay_nonce: behavior matched.' --idempotency-key 'observe-B6_replay_nonce' --json`
- `node packages/cli/dist/index.js showcase record-verdict --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_b6_replay_nonce' --item 'item.tiers.approval.happy_path' --verdict pass --idempotency-key 'verdict-B6_replay_nonce' --json`
- `node packages/cli/dist/index.js showcase finish --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_b6_replay_nonce' --idempotency-key 'finish-B6_replay_nonce' --json`
- `node packages/cli/dist/index.js showcase request-approval --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_b6_replay_nonce' --json > '/tmp/uc-tiers-acceptance/outputs/B6_replay_nonce.request.json'`
- `node packages/cli/dist/index.js approve-run --request '/tmp/uc-tiers-acceptance/outputs/B6_replay_nonce.request.json' --key-file '/tmp/uc-tiers-acceptance/keys/trusted/ci-signing-key.pem' --key-id 'trusted-host' --decision 'approved' --out '/tmp/uc-tiers-acceptance/outputs/B6_replay_nonce.token.json' --json`
- `node packages/cli/dist/index.js showcase approve --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_b6_replay_nonce' --statement 'Attack B6_replay_nonce_first' --approval-token '/tmp/uc-tiers-acceptance/outputs/B6_replay_nonce.token.json' --idempotency-key 'approve-B6_replay_nonce_first' --json`

Attack command: `node packages/cli/dist/index.js showcase approve --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_b6_replay_nonce' --statement 'Replay same token' --approval-token '/tmp/uc-tiers-acceptance/outputs/B6_replay_nonce.token.json' --idempotency-key 'approve-B6_replay_nonce-second' --json`

Actual output:

```text
exit=1
{"schema_version":1,"protocol_version":1,"command":"showcase.approve","ok":false,"complete":false,"data":{},"diagnostics":[{"code":"showcase.approval_nonce_burned","severity":"error","message":"User approval token rejected: NONCE_BURNED (approval token nonce already burned (replay))","source_path":null,"json_pointer":null,"entity_id":null,"related_ids":[]}],"context":{"workspace_root":"/Users/admin/repos/use-case-matrix-g2-attack","data_root":"/Users/admin/repos/use-case-matrix-g2-attack","component_id":"use-cases","workspace_snapshot":{"repository_id":"unknown","vcs":"unknown","head_revision":"unknown","dirty":false,"working_tree_digest":"sha256:0000000000000000000000000000000000000000000000000000000000000000","component_id":"use-cases","captured_at":"1970-01-01T00:00:00.000Z"}}}
```

Verdict: PASS - attack was blocked/fail-closed.

### PASS - B7_agent_self_approval: B7 agent self-approval

Attack: Use a pinned automation-tier key with assurance_method automation.

Expected: Rejected/fail-closed: assurance too low.

Prep commands:

- `node packages/cli/dist/index.js showcase start --repo '/tmp/uc-tiers-acceptance/workspace' --adhoc --select 'tiers.approval.happy_path' --idempotency-key 'start-B7_agent_self_approval' --json`
- `node packages/cli/dist/index.js showcase record-observation --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_b7_agent_self_approval' --item 'item.tiers.approval.happy_path' --text 'Observation for B7_agent_self_approval: behavior matched.' --idempotency-key 'observe-B7_agent_self_approval' --json`
- `node packages/cli/dist/index.js showcase record-verdict --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_b7_agent_self_approval' --item 'item.tiers.approval.happy_path' --verdict pass --idempotency-key 'verdict-B7_agent_self_approval' --json`
- `node packages/cli/dist/index.js showcase finish --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_b7_agent_self_approval' --idempotency-key 'finish-B7_agent_self_approval' --json`
- `node packages/cli/dist/index.js showcase request-approval --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_b7_agent_self_approval' --json > '/tmp/uc-tiers-acceptance/outputs/B7_agent_self_approval.request.json'`
- `node packages/cli/dist/index.js approve-run --request '/tmp/uc-tiers-acceptance/outputs/B7_agent_self_approval.request.json' --key-file '/tmp/uc-tiers-acceptance/keys/agent/ci-signing-key.pem' --key-id 'agent-automation' --decision 'approved' --assurance-method 'automation' --out '/tmp/uc-tiers-acceptance/outputs/B7_agent_self_approval.token.json' --json`

Attack command: `node packages/cli/dist/index.js showcase approve --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_b7_agent_self_approval' --statement 'Attack B7_agent_self_approval' --approval-token '/tmp/uc-tiers-acceptance/outputs/B7_agent_self_approval.token.json' --idempotency-key 'approve-B7_agent_self_approval' --json`

Actual output:

```text
exit=1
{"schema_version":1,"protocol_version":1,"command":"showcase.approve","ok":false,"complete":false,"data":{},"diagnostics":[{"code":"showcase.approval_assurance_too_low","severity":"error","message":"User approval token rejected: ASSURANCE_TOO_LOW (approval token assurance tier untrusted_automation does not meet floor trusted_host_user_presence)","source_path":null,"json_pointer":null,"entity_id":null,"related_ids":[]}],"context":{"workspace_root":"/Users/admin/repos/use-case-matrix-g2-attack","data_root":"/Users/admin/repos/use-case-matrix-g2-attack","component_id":"use-cases","workspace_snapshot":{"repository_id":"unknown","vcs":"unknown","head_revision":"unknown","dirty":false,"working_tree_digest":"sha256:0000000000000000000000000000000000000000000000000000000000000000","component_id":"use-cases","captured_at":"1970-01-01T00:00:00.000Z"}}}
```

Verdict: PASS - attack was blocked/fail-closed.

### PASS - B8_run_mutated_after_approval: B8 run mutated after approval

Attack: Approve a run, append another observation after approval, then replay status.

Expected: Fail-closed: approval_state becomes stale_due_to_run_change.

Prep commands:

- `node packages/cli/dist/index.js showcase start --repo '/tmp/uc-tiers-acceptance/workspace' --adhoc --select 'tiers.approval.happy_path' --idempotency-key 'start-B8_run_mutated_after_approval' --json`
- `node packages/cli/dist/index.js showcase record-observation --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_b8_run_mutated_after_approval' --item 'item.tiers.approval.happy_path' --text 'Observation for B8_run_mutated_after_approval: behavior matched.' --idempotency-key 'observe-B8_run_mutated_after_approval' --json`
- `node packages/cli/dist/index.js showcase record-verdict --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_b8_run_mutated_after_approval' --item 'item.tiers.approval.happy_path' --verdict pass --idempotency-key 'verdict-B8_run_mutated_after_approval' --json`
- `node packages/cli/dist/index.js showcase finish --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_b8_run_mutated_after_approval' --idempotency-key 'finish-B8_run_mutated_after_approval' --json`
- `node packages/cli/dist/index.js showcase request-approval --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_b8_run_mutated_after_approval' --json > '/tmp/uc-tiers-acceptance/outputs/B8_run_mutated_after_approval.request.json'`
- `node packages/cli/dist/index.js approve-run --request '/tmp/uc-tiers-acceptance/outputs/B8_run_mutated_after_approval.request.json' --key-file '/tmp/uc-tiers-acceptance/keys/trusted/ci-signing-key.pem' --key-id 'trusted-host' --decision 'approved' --out '/tmp/uc-tiers-acceptance/outputs/B8_run_mutated_after_approval.token.json' --json`
- `node packages/cli/dist/index.js showcase approve --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_b8_run_mutated_after_approval' --statement 'Attack B8_run_mutated_after_approval' --approval-token '/tmp/uc-tiers-acceptance/outputs/B8_run_mutated_after_approval.token.json' --idempotency-key 'approve-B8_run_mutated_after_approval' --json`
- `node packages/cli/dist/index.js showcase record-observation --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_b8_run_mutated_after_approval' --item 'item.tiers.approval.happy_path' --text 'Post-approval mutation' --idempotency-key 'mutate-B8_run_mutated_after_approval' --json`

Attack command: `node packages/cli/dist/index.js showcase status --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_b8_run_mutated_after_approval' --json`

Actual output:

```text
exit=0
{"schema_version":1,"protocol_version":1,"command":"showcase.status","ok":true,"complete":true,"data":{"schema_version":1,"run_id":"run.start_b8_run_mutated_after_approval","complete":true,"execution_status":"completed","run_outcome":"passed","approval_state":"stale_due_to_run_change","unresolved_failure_count":0,"items":[{"plan_item_id":"item.tiers.approval.happy_path","verdict":"pass","item_currency":"current","verification_state":"requirements_met","latest_observation_event_id":"evt.run.start_b8_run_mutated_after_approval.7","latest_verdict_event_id":"evt.run.start_b8_run_mutated_after_approval.3"}],"known_gaps":[],"diagnostic_summary":{}},"diagnostics":[],"context":{"workspace_root":"/private/tmp/uc-tiers-acceptance/workspace","data_root":"/private/tmp/uc-tiers-acceptance/workspace","component_id":"tiers","workspace_snapshot":{"repository_id":"unknown","vcs":"unknown","head_revision":"unknown","dirty":false,"working_tree_digest":"sha256:0000000000000000000000000000000000000000000000000000000000000000","component_id":"tiers","captured_at":"1970-01-01T00:00:00.000Z"}}}
```

Verdict: PASS - attack was blocked/fail-closed.

### PASS - B9a_rejected_token_via_approve: B9 rejected token via approve

Attack: Submit a token whose signed decision is rejected to showcase approve.

Expected: Rejected/fail-closed: DECISION_MISMATCH.

Prep commands:

- `node packages/cli/dist/index.js showcase start --repo '/tmp/uc-tiers-acceptance/workspace' --adhoc --select 'tiers.approval.happy_path' --idempotency-key 'start-B9a_rejected_token_via_approve' --json`
- `node packages/cli/dist/index.js showcase record-observation --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_b9a_rejected_token_via_approve' --item 'item.tiers.approval.happy_path' --text 'Observation for B9a_rejected_token_via_approve: behavior matched.' --idempotency-key 'observe-B9a_rejected_token_via_approve' --json`
- `node packages/cli/dist/index.js showcase record-verdict --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_b9a_rejected_token_via_approve' --item 'item.tiers.approval.happy_path' --verdict pass --idempotency-key 'verdict-B9a_rejected_token_via_approve' --json`
- `node packages/cli/dist/index.js showcase finish --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_b9a_rejected_token_via_approve' --idempotency-key 'finish-B9a_rejected_token_via_approve' --json`
- `node packages/cli/dist/index.js showcase request-approval --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_b9a_rejected_token_via_approve' --json > '/tmp/uc-tiers-acceptance/outputs/B9a_rejected_token_via_approve.request.json'`
- `node packages/cli/dist/index.js approve-run --request '/tmp/uc-tiers-acceptance/outputs/B9a_rejected_token_via_approve.request.json' --key-file '/tmp/uc-tiers-acceptance/keys/trusted/ci-signing-key.pem' --key-id 'trusted-host' --decision 'rejected' --out '/tmp/uc-tiers-acceptance/outputs/B9a_rejected_token_via_approve.token.json' --json`

Attack command: `node packages/cli/dist/index.js showcase approve --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_b9a_rejected_token_via_approve' --statement 'Attack B9a_rejected_token_via_approve' --approval-token '/tmp/uc-tiers-acceptance/outputs/B9a_rejected_token_via_approve.token.json' --idempotency-key 'approve-B9a_rejected_token_via_approve' --json`

Actual output:

```text
exit=1
{"schema_version":1,"protocol_version":1,"command":"showcase.approve","ok":false,"complete":false,"data":{},"diagnostics":[{"code":"showcase.approval_decision_mismatch","severity":"error","message":"User approval token rejected: DECISION_MISMATCH (rejected token cannot record approval)","source_path":null,"json_pointer":null,"entity_id":null,"related_ids":[]}],"context":{"workspace_root":"/Users/admin/repos/use-case-matrix-g2-attack","data_root":"/Users/admin/repos/use-case-matrix-g2-attack","component_id":"use-cases","workspace_snapshot":{"repository_id":"unknown","vcs":"unknown","head_revision":"unknown","dirty":false,"working_tree_digest":"sha256:0000000000000000000000000000000000000000000000000000000000000000","component_id":"use-cases","captured_at":"1970-01-01T00:00:00.000Z"}}}
```

Verdict: PASS - attack was blocked/fail-closed.

### PASS - B9b_approved_token_via_reject: B9 approved token via reject

Attack: Submit a token whose signed decision is approved to showcase reject.

Expected: Rejected/fail-closed: DECISION_MISMATCH.

Prep commands:

- `node packages/cli/dist/index.js showcase start --repo '/tmp/uc-tiers-acceptance/workspace' --adhoc --select 'tiers.approval.happy_path' --idempotency-key 'start-B9b_approved_token_via_reject' --json`
- `node packages/cli/dist/index.js showcase record-observation --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_b9b_approved_token_via_reject' --item 'item.tiers.approval.happy_path' --text 'Observation for B9b_approved_token_via_reject: behavior matched.' --idempotency-key 'observe-B9b_approved_token_via_reject' --json`
- `node packages/cli/dist/index.js showcase record-verdict --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_b9b_approved_token_via_reject' --item 'item.tiers.approval.happy_path' --verdict pass --idempotency-key 'verdict-B9b_approved_token_via_reject' --json`
- `node packages/cli/dist/index.js showcase finish --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_b9b_approved_token_via_reject' --idempotency-key 'finish-B9b_approved_token_via_reject' --json`
- `node packages/cli/dist/index.js showcase request-approval --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_b9b_approved_token_via_reject' --json > '/tmp/uc-tiers-acceptance/outputs/B9b_approved_token_via_reject.request.json'`
- `node packages/cli/dist/index.js approve-run --request '/tmp/uc-tiers-acceptance/outputs/B9b_approved_token_via_reject.request.json' --key-file '/tmp/uc-tiers-acceptance/keys/trusted/ci-signing-key.pem' --key-id 'trusted-host' --decision 'approved' --out '/tmp/uc-tiers-acceptance/outputs/B9b_approved_token_via_reject.token.json' --json`

Attack command: `node packages/cli/dist/index.js showcase reject --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_b9b_approved_token_via_reject' --statement 'Attack B9b_approved_token_via_reject' --approval-token '/tmp/uc-tiers-acceptance/outputs/B9b_approved_token_via_reject.token.json' --idempotency-key 'reject-B9b_approved_token_via_reject' --json`

Actual output:

```text
exit=1
{"schema_version":1,"protocol_version":1,"command":"showcase.reject","ok":false,"complete":false,"data":{},"diagnostics":[{"code":"showcase.approval_decision_mismatch","severity":"error","message":"User approval token rejected: DECISION_MISMATCH (approval token cannot record rejection)","source_path":null,"json_pointer":null,"entity_id":null,"related_ids":[]}],"context":{"workspace_root":"/Users/admin/repos/use-case-matrix-g2-attack","data_root":"/Users/admin/repos/use-case-matrix-g2-attack","component_id":"use-cases","workspace_snapshot":{"repository_id":"unknown","vcs":"unknown","head_revision":"unknown","dirty":false,"working_tree_digest":"sha256:0000000000000000000000000000000000000000000000000000000000000000","component_id":"use-cases","captured_at":"1970-01-01T00:00:00.000Z"}}}
```

Verdict: PASS - attack was blocked/fail-closed.

### PASS - N1a_pinned_anchor_blocks_keyring: N1 X1 closed: unpinned signer via --keyring

Attack: Sign with rogue-host, then pass a rogue --keyring to try to nominate a new trust root.

Expected: Rejected/fail-closed: signer is not in pinned approval_trust.

Prep commands:

- `node packages/cli/dist/index.js showcase start --repo '/tmp/uc-tiers-acceptance/workspace' --adhoc --select 'tiers.approval.happy_path' --idempotency-key 'start-N1a_pinned_anchor_blocks_keyring' --json`
- `node packages/cli/dist/index.js showcase record-observation --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_n1a_pinned_anchor_blocks_keyring' --item 'item.tiers.approval.happy_path' --text 'Observation for N1a_pinned_anchor_blocks_keyring: behavior matched.' --idempotency-key 'observe-N1a_pinned_anchor_blocks_keyring' --json`
- `node packages/cli/dist/index.js showcase record-verdict --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_n1a_pinned_anchor_blocks_keyring' --item 'item.tiers.approval.happy_path' --verdict pass --idempotency-key 'verdict-N1a_pinned_anchor_blocks_keyring' --json`
- `node packages/cli/dist/index.js showcase finish --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_n1a_pinned_anchor_blocks_keyring' --idempotency-key 'finish-N1a_pinned_anchor_blocks_keyring' --json`
- `node packages/cli/dist/index.js showcase request-approval --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_n1a_pinned_anchor_blocks_keyring' --json > '/tmp/uc-tiers-acceptance/outputs/N1a_pinned_anchor_blocks_keyring.request.json'`
- `node packages/cli/dist/index.js approve-run --request '/tmp/uc-tiers-acceptance/outputs/N1a_pinned_anchor_blocks_keyring.request.json' --key-file '/tmp/uc-tiers-acceptance/keys/wrong/ci-signing-key.pem' --key-id 'rogue-host' --decision 'approved' --out '/tmp/uc-tiers-acceptance/outputs/N1a_pinned_anchor_blocks_keyring.token.json' --json`

Attack command: `node packages/cli/dist/index.js showcase approve --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_n1a_pinned_anchor_blocks_keyring' --statement 'Attack N1a_pinned_anchor_blocks_keyring' --approval-token '/tmp/uc-tiers-acceptance/outputs/N1a_pinned_anchor_blocks_keyring.token.json' --keyring '/tmp/uc-tiers-acceptance/rogue-keyring.json' --idempotency-key 'approve-N1a_pinned_anchor_blocks_keyring' --json`

Actual output:

```text
exit=1
{"schema_version":1,"protocol_version":1,"command":"showcase.approve","ok":false,"complete":false,"data":{},"diagnostics":[{"code":"showcase.approval_trust_anchor_unpinned","severity":"error","message":"approval token signer 'rogue-host' is not in pinned approval_trust.","source_path":null,"json_pointer":null,"entity_id":null,"related_ids":[]}],"context":{"workspace_root":"/Users/admin/repos/use-case-matrix-g2-attack","data_root":"/Users/admin/repos/use-case-matrix-g2-attack","component_id":"use-cases","workspace_snapshot":{"repository_id":"unknown","vcs":"unknown","head_revision":"unknown","dirty":false,"working_tree_digest":"sha256:0000000000000000000000000000000000000000000000000000000000000000","component_id":"use-cases","captured_at":"1970-01-01T00:00:00.000Z"}}}
```

Verdict: PASS - attack was blocked/fail-closed.

### PASS - N1b_pinned_anchor_blocks_public_key: N1 X1 closed: unpinned signer via --public-key

Attack: Sign with rogue-host, then pass the rogue --public-key to try to nominate a new trust root.

Expected: Rejected/fail-closed: signer is not in pinned approval_trust.

Prep commands:

- `node packages/cli/dist/index.js showcase start --repo '/tmp/uc-tiers-acceptance/workspace' --adhoc --select 'tiers.approval.happy_path' --idempotency-key 'start-N1b_pinned_anchor_blocks_public_key' --json`
- `node packages/cli/dist/index.js showcase record-observation --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_n1b_pinned_anchor_blocks_public_key' --item 'item.tiers.approval.happy_path' --text 'Observation for N1b_pinned_anchor_blocks_public_key: behavior matched.' --idempotency-key 'observe-N1b_pinned_anchor_blocks_public_key' --json`
- `node packages/cli/dist/index.js showcase record-verdict --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_n1b_pinned_anchor_blocks_public_key' --item 'item.tiers.approval.happy_path' --verdict pass --idempotency-key 'verdict-N1b_pinned_anchor_blocks_public_key' --json`
- `node packages/cli/dist/index.js showcase finish --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_n1b_pinned_anchor_blocks_public_key' --idempotency-key 'finish-N1b_pinned_anchor_blocks_public_key' --json`
- `node packages/cli/dist/index.js showcase request-approval --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_n1b_pinned_anchor_blocks_public_key' --json > '/tmp/uc-tiers-acceptance/outputs/N1b_pinned_anchor_blocks_public_key.request.json'`
- `node packages/cli/dist/index.js approve-run --request '/tmp/uc-tiers-acceptance/outputs/N1b_pinned_anchor_blocks_public_key.request.json' --key-file '/tmp/uc-tiers-acceptance/keys/wrong/ci-signing-key.pem' --key-id 'rogue-host' --decision 'approved' --out '/tmp/uc-tiers-acceptance/outputs/N1b_pinned_anchor_blocks_public_key.token.json' --json`

Attack command: `node packages/cli/dist/index.js showcase approve --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_n1b_pinned_anchor_blocks_public_key' --statement 'Attack N1b_pinned_anchor_blocks_public_key' --approval-token '/tmp/uc-tiers-acceptance/outputs/N1b_pinned_anchor_blocks_public_key.token.json' --public-key '/tmp/uc-tiers-acceptance/rogue.pub.pem' --idempotency-key 'approve-N1b_pinned_anchor_blocks_public_key' --json`

Actual output:

```text
exit=1
{"schema_version":1,"protocol_version":1,"command":"showcase.approve","ok":false,"complete":false,"data":{},"diagnostics":[{"code":"showcase.approval_trust_anchor_unpinned","severity":"error","message":"approval token signer 'rogue-host' is not in pinned approval_trust.","source_path":null,"json_pointer":null,"entity_id":null,"related_ids":[]}],"context":{"workspace_root":"/Users/admin/repos/use-case-matrix-g2-attack","data_root":"/Users/admin/repos/use-case-matrix-g2-attack","component_id":"use-cases","workspace_snapshot":{"repository_id":"unknown","vcs":"unknown","head_revision":"unknown","dirty":false,"working_tree_digest":"sha256:0000000000000000000000000000000000000000000000000000000000000000","component_id":"use-cases","captured_at":"1970-01-01T00:00:00.000Z"}}}
```

Verdict: PASS - attack was blocked/fail-closed.

### PASS - N2_over_claim_same_channel_key: N2 over-claim

Attack: Use a same-channel-capped key to sign a token claiming os_presence.

Expected: Rejected/fail-closed: ASSURANCE_OVER_CLAIM.

Prep commands:

- `node packages/cli/dist/index.js showcase start --repo '/tmp/uc-tiers-acceptance/workspace' --adhoc --select 'tiers.approval.happy_path' --idempotency-key 'start-N2_over_claim_same_channel_key' --json`
- `node packages/cli/dist/index.js showcase record-observation --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_n2_over_claim_same_channel_key' --item 'item.tiers.approval.happy_path' --text 'Observation for N2_over_claim_same_channel_key: behavior matched.' --idempotency-key 'observe-N2_over_claim_same_channel_key' --json`
- `node packages/cli/dist/index.js showcase record-verdict --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_n2_over_claim_same_channel_key' --item 'item.tiers.approval.happy_path' --verdict pass --idempotency-key 'verdict-N2_over_claim_same_channel_key' --json`
- `node packages/cli/dist/index.js showcase finish --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_n2_over_claim_same_channel_key' --idempotency-key 'finish-N2_over_claim_same_channel_key' --json`
- `node packages/cli/dist/index.js showcase request-approval --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_n2_over_claim_same_channel_key' --json > '/tmp/uc-tiers-acceptance/outputs/N2_over_claim_same_channel_key.request.json'`
- `node packages/cli/dist/index.js approve-run --request '/tmp/uc-tiers-acceptance/outputs/N2_over_claim_same_channel_key.request.json' --key-file '/tmp/uc-tiers-acceptance/keys/same/ci-signing-key.pem' --key-id 'same-channel' --decision 'approved' --assurance-method 'os_presence' --out '/tmp/uc-tiers-acceptance/outputs/N2_over_claim_same_channel_key.token.json' --json`

Attack command: `node packages/cli/dist/index.js showcase approve --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_n2_over_claim_same_channel_key' --statement 'Attack N2_over_claim_same_channel_key' --approval-token '/tmp/uc-tiers-acceptance/outputs/N2_over_claim_same_channel_key.token.json' --idempotency-key 'approve-N2_over_claim_same_channel_key' --json`

Actual output:

```text
exit=1
{"schema_version":1,"protocol_version":1,"command":"showcase.approve","ok":false,"complete":false,"data":{},"diagnostics":[{"code":"showcase.approval_assurance_over_claim","severity":"error","message":"User approval token rejected: ASSURANCE_OVER_CLAIM (approval token claims assurance tier trusted_host_user_presence above key same-channel cap same_channel_operator_confirmation)","source_path":null,"json_pointer":null,"entity_id":null,"related_ids":[]}],"context":{"workspace_root":"/Users/admin/repos/use-case-matrix-g2-attack","data_root":"/Users/admin/repos/use-case-matrix-g2-attack","component_id":"use-cases","workspace_snapshot":{"repository_id":"unknown","vcs":"unknown","head_revision":"unknown","dirty":false,"working_tree_digest":"sha256:0000000000000000000000000000000000000000000000000000000000000000","component_id":"use-cases","captured_at":"1970-01-01T00:00:00.000Z"}}}
```

Verdict: PASS - attack was blocked/fail-closed.

### PASS - N3a_webauthn_wrong_challenge: N3a WebAuthn wrong challenge

Attack: Use a WebAuthn assertion whose clientDataJSON.challenge is not sha256(binding).

Expected: WEBAUTHN_CHALLENGE_MISMATCH

Prep commands:

- `node packages/cli/dist/index.js showcase start --repo '/tmp/uc-tiers-acceptance/workspace' --adhoc --select 'tiers.approval.happy_path' --idempotency-key 'start-N3a_webauthn_wrong_challenge' --json`
- `node packages/cli/dist/index.js showcase record-observation --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_n3a_webauthn_wrong_challenge' --item 'item.tiers.approval.happy_path' --text 'Observation for N3a_webauthn_wrong_challenge: behavior matched.' --idempotency-key 'observe-N3a_webauthn_wrong_challenge' --json`
- `node packages/cli/dist/index.js showcase record-verdict --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_n3a_webauthn_wrong_challenge' --item 'item.tiers.approval.happy_path' --verdict pass --idempotency-key 'verdict-N3a_webauthn_wrong_challenge' --json`
- `node packages/cli/dist/index.js showcase finish --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_n3a_webauthn_wrong_challenge' --idempotency-key 'finish-N3a_webauthn_wrong_challenge' --json`
- `node packages/cli/dist/index.js showcase request-approval --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_n3a_webauthn_wrong_challenge' --json > '/tmp/uc-tiers-acceptance/outputs/N3a_webauthn_wrong_challenge.request.json'`
- `node packages/cli/dist/index.js approve-run --request '/tmp/uc-tiers-acceptance/outputs/N3a_webauthn_wrong_challenge.request.json' --webauthn-assertion '/tmp/uc-tiers-acceptance/outputs/N3a_webauthn_wrong_challenge.assertion.json' --decision 'approved' --out '/tmp/uc-tiers-acceptance/outputs/N3a_webauthn_wrong_challenge.token.json' --json`

Attack command: `node packages/cli/dist/index.js showcase approve --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_n3a_webauthn_wrong_challenge' --statement 'Attack N3a_webauthn_wrong_challenge' --approval-token '/tmp/uc-tiers-acceptance/outputs/N3a_webauthn_wrong_challenge.token.json' --idempotency-key 'approve-N3a_webauthn_wrong_challenge' --json`

Actual output:

```text
exit=1
{"schema_version":1,"protocol_version":1,"command":"showcase.approve","ok":false,"complete":false,"data":{},"diagnostics":[{"code":"showcase.trusted_user_confirmation_required","severity":"error","message":"User approval token rejected: WEBAUTHN_CHALLENGE_MISMATCH (webauthn clientDataJSON.challenge does not match this approval binding)","source_path":null,"json_pointer":null,"entity_id":null,"related_ids":[]}],"context":{"workspace_root":"/Users/admin/repos/use-case-matrix-g2-attack","data_root":"/Users/admin/repos/use-case-matrix-g2-attack","component_id":"use-cases","workspace_snapshot":{"repository_id":"unknown","vcs":"unknown","head_revision":"unknown","dirty":false,"working_tree_digest":"sha256:0000000000000000000000000000000000000000000000000000000000000000","component_id":"use-cases","captured_at":"1970-01-01T00:00:00.000Z"}}}
```

Verdict: PASS - attack was blocked/fail-closed.

### PASS - N3b_webauthn_up_unset: N3b WebAuthn UP flag unset

Attack: Use authenticatorData with UV set but UP unset.

Expected: WEBAUTHN_USER_NOT_PRESENT

Prep commands:

- `node packages/cli/dist/index.js showcase start --repo '/tmp/uc-tiers-acceptance/workspace' --adhoc --select 'tiers.approval.happy_path' --idempotency-key 'start-N3b_webauthn_up_unset' --json`
- `node packages/cli/dist/index.js showcase record-observation --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_n3b_webauthn_up_unset' --item 'item.tiers.approval.happy_path' --text 'Observation for N3b_webauthn_up_unset: behavior matched.' --idempotency-key 'observe-N3b_webauthn_up_unset' --json`
- `node packages/cli/dist/index.js showcase record-verdict --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_n3b_webauthn_up_unset' --item 'item.tiers.approval.happy_path' --verdict pass --idempotency-key 'verdict-N3b_webauthn_up_unset' --json`
- `node packages/cli/dist/index.js showcase finish --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_n3b_webauthn_up_unset' --idempotency-key 'finish-N3b_webauthn_up_unset' --json`
- `node packages/cli/dist/index.js showcase request-approval --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_n3b_webauthn_up_unset' --json > '/tmp/uc-tiers-acceptance/outputs/N3b_webauthn_up_unset.request.json'`
- `node packages/cli/dist/index.js approve-run --request '/tmp/uc-tiers-acceptance/outputs/N3b_webauthn_up_unset.request.json' --webauthn-assertion '/tmp/uc-tiers-acceptance/outputs/N3b_webauthn_up_unset.assertion.json' --decision 'approved' --out '/tmp/uc-tiers-acceptance/outputs/N3b_webauthn_up_unset.token.json' --json`

Attack command: `node packages/cli/dist/index.js showcase approve --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_n3b_webauthn_up_unset' --statement 'Attack N3b_webauthn_up_unset' --approval-token '/tmp/uc-tiers-acceptance/outputs/N3b_webauthn_up_unset.token.json' --idempotency-key 'approve-N3b_webauthn_up_unset' --json`

Actual output:

```text
exit=1
{"schema_version":1,"protocol_version":1,"command":"showcase.approve","ok":false,"complete":false,"data":{},"diagnostics":[{"code":"showcase.trusted_user_confirmation_required","severity":"error","message":"User approval token rejected: WEBAUTHN_USER_NOT_PRESENT (webauthn assertion did not set the UP flag)","source_path":null,"json_pointer":null,"entity_id":null,"related_ids":[]}],"context":{"workspace_root":"/Users/admin/repos/use-case-matrix-g2-attack","data_root":"/Users/admin/repos/use-case-matrix-g2-attack","component_id":"use-cases","workspace_snapshot":{"repository_id":"unknown","vcs":"unknown","head_revision":"unknown","dirty":false,"working_tree_digest":"sha256:0000000000000000000000000000000000000000000000000000000000000000","component_id":"use-cases","captured_at":"1970-01-01T00:00:00.000Z"}}}
```

Verdict: PASS - attack was blocked/fail-closed.

### PASS - N3c_webauthn_uv_unset: N3c WebAuthn UV flag unset

Attack: Use authenticatorData with UP set but UV unset.

Expected: WEBAUTHN_USER_NOT_VERIFIED

Prep commands:

- `node packages/cli/dist/index.js showcase start --repo '/tmp/uc-tiers-acceptance/workspace' --adhoc --select 'tiers.approval.happy_path' --idempotency-key 'start-N3c_webauthn_uv_unset' --json`
- `node packages/cli/dist/index.js showcase record-observation --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_n3c_webauthn_uv_unset' --item 'item.tiers.approval.happy_path' --text 'Observation for N3c_webauthn_uv_unset: behavior matched.' --idempotency-key 'observe-N3c_webauthn_uv_unset' --json`
- `node packages/cli/dist/index.js showcase record-verdict --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_n3c_webauthn_uv_unset' --item 'item.tiers.approval.happy_path' --verdict pass --idempotency-key 'verdict-N3c_webauthn_uv_unset' --json`
- `node packages/cli/dist/index.js showcase finish --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_n3c_webauthn_uv_unset' --idempotency-key 'finish-N3c_webauthn_uv_unset' --json`
- `node packages/cli/dist/index.js showcase request-approval --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_n3c_webauthn_uv_unset' --json > '/tmp/uc-tiers-acceptance/outputs/N3c_webauthn_uv_unset.request.json'`
- `node packages/cli/dist/index.js approve-run --request '/tmp/uc-tiers-acceptance/outputs/N3c_webauthn_uv_unset.request.json' --webauthn-assertion '/tmp/uc-tiers-acceptance/outputs/N3c_webauthn_uv_unset.assertion.json' --decision 'approved' --out '/tmp/uc-tiers-acceptance/outputs/N3c_webauthn_uv_unset.token.json' --json`

Attack command: `node packages/cli/dist/index.js showcase approve --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_n3c_webauthn_uv_unset' --statement 'Attack N3c_webauthn_uv_unset' --approval-token '/tmp/uc-tiers-acceptance/outputs/N3c_webauthn_uv_unset.token.json' --idempotency-key 'approve-N3c_webauthn_uv_unset' --json`

Actual output:

```text
exit=1
{"schema_version":1,"protocol_version":1,"command":"showcase.approve","ok":false,"complete":false,"data":{},"diagnostics":[{"code":"showcase.trusted_user_confirmation_required","severity":"error","message":"User approval token rejected: WEBAUTHN_USER_NOT_VERIFIED (webauthn assertion did not set the UV flag)","source_path":null,"json_pointer":null,"entity_id":null,"related_ids":[]}],"context":{"workspace_root":"/Users/admin/repos/use-case-matrix-g2-attack","data_root":"/Users/admin/repos/use-case-matrix-g2-attack","component_id":"use-cases","workspace_snapshot":{"repository_id":"unknown","vcs":"unknown","head_revision":"unknown","dirty":false,"working_tree_digest":"sha256:0000000000000000000000000000000000000000000000000000000000000000","component_id":"use-cases","captured_at":"1970-01-01T00:00:00.000Z"}}}
```

Verdict: PASS - attack was blocked/fail-closed.

### PASS - N3d1_webauthn_tampered_authenticator_data: N3d WebAuthn tampered authenticator_data

Attack: Flip one byte of authenticator_data after signing.

Expected: WEBAUTHN_BAD_SIGNATURE

Prep commands:

- `node packages/cli/dist/index.js showcase start --repo '/tmp/uc-tiers-acceptance/workspace' --adhoc --select 'tiers.approval.happy_path' --idempotency-key 'start-N3d1_webauthn_tampered_authenticator_data' --json`
- `node packages/cli/dist/index.js showcase record-observation --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_n3d1_webauthn_tampered_authenticator_data' --item 'item.tiers.approval.happy_path' --text 'Observation for N3d1_webauthn_tampered_authenticator_data: behavior matched.' --idempotency-key 'observe-N3d1_webauthn_tampered_authenticator_data' --json`
- `node packages/cli/dist/index.js showcase record-verdict --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_n3d1_webauthn_tampered_authenticator_data' --item 'item.tiers.approval.happy_path' --verdict pass --idempotency-key 'verdict-N3d1_webauthn_tampered_authenticator_data' --json`
- `node packages/cli/dist/index.js showcase finish --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_n3d1_webauthn_tampered_authenticator_data' --idempotency-key 'finish-N3d1_webauthn_tampered_authenticator_data' --json`
- `node packages/cli/dist/index.js showcase request-approval --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_n3d1_webauthn_tampered_authenticator_data' --json > '/tmp/uc-tiers-acceptance/outputs/N3d1_webauthn_tampered_authenticator_data.request.json'`
- `node packages/cli/dist/index.js approve-run --request '/tmp/uc-tiers-acceptance/outputs/N3d1_webauthn_tampered_authenticator_data.request.json' --webauthn-assertion '/tmp/uc-tiers-acceptance/outputs/N3d1_webauthn_tampered_authenticator_data.assertion.json' --decision 'approved' --out '/tmp/uc-tiers-acceptance/outputs/N3d1_webauthn_tampered_authenticator_data.token.json' --json`

Attack command: `node packages/cli/dist/index.js showcase approve --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_n3d1_webauthn_tampered_authenticator_data' --statement 'Attack N3d1_webauthn_tampered_authenticator_data' --approval-token '/tmp/uc-tiers-acceptance/outputs/N3d1_webauthn_tampered_authenticator_data.token.json' --idempotency-key 'approve-N3d1_webauthn_tampered_authenticator_data' --json`

Actual output:

```text
exit=1
{"schema_version":1,"protocol_version":1,"command":"showcase.approve","ok":false,"complete":false,"data":{},"diagnostics":[{"code":"showcase.trusted_user_confirmation_required","severity":"error","message":"User approval token rejected: WEBAUTHN_BAD_SIGNATURE (webauthn signature for credential_id webauthn-trusted did not verify)","source_path":null,"json_pointer":null,"entity_id":null,"related_ids":[]}],"context":{"workspace_root":"/Users/admin/repos/use-case-matrix-g2-attack","data_root":"/Users/admin/repos/use-case-matrix-g2-attack","component_id":"use-cases","workspace_snapshot":{"repository_id":"unknown","vcs":"unknown","head_revision":"unknown","dirty":false,"working_tree_digest":"sha256:0000000000000000000000000000000000000000000000000000000000000000","component_id":"use-cases","captured_at":"1970-01-01T00:00:00.000Z"}}}
```

Verdict: PASS - attack was blocked/fail-closed.

### PASS - N3d2_webauthn_tampered_signature: N3d WebAuthn tampered signature

Attack: Flip one byte of the WebAuthn assertion signature.

Expected: WEBAUTHN_BAD_SIGNATURE

Prep commands:

- `node packages/cli/dist/index.js showcase start --repo '/tmp/uc-tiers-acceptance/workspace' --adhoc --select 'tiers.approval.happy_path' --idempotency-key 'start-N3d2_webauthn_tampered_signature' --json`
- `node packages/cli/dist/index.js showcase record-observation --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_n3d2_webauthn_tampered_signature' --item 'item.tiers.approval.happy_path' --text 'Observation for N3d2_webauthn_tampered_signature: behavior matched.' --idempotency-key 'observe-N3d2_webauthn_tampered_signature' --json`
- `node packages/cli/dist/index.js showcase record-verdict --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_n3d2_webauthn_tampered_signature' --item 'item.tiers.approval.happy_path' --verdict pass --idempotency-key 'verdict-N3d2_webauthn_tampered_signature' --json`
- `node packages/cli/dist/index.js showcase finish --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_n3d2_webauthn_tampered_signature' --idempotency-key 'finish-N3d2_webauthn_tampered_signature' --json`
- `node packages/cli/dist/index.js showcase request-approval --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_n3d2_webauthn_tampered_signature' --json > '/tmp/uc-tiers-acceptance/outputs/N3d2_webauthn_tampered_signature.request.json'`
- `node packages/cli/dist/index.js approve-run --request '/tmp/uc-tiers-acceptance/outputs/N3d2_webauthn_tampered_signature.request.json' --webauthn-assertion '/tmp/uc-tiers-acceptance/outputs/N3d2_webauthn_tampered_signature.assertion.json' --decision 'approved' --out '/tmp/uc-tiers-acceptance/outputs/N3d2_webauthn_tampered_signature.token.json' --json`

Attack command: `node packages/cli/dist/index.js showcase approve --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_n3d2_webauthn_tampered_signature' --statement 'Attack N3d2_webauthn_tampered_signature' --approval-token '/tmp/uc-tiers-acceptance/outputs/N3d2_webauthn_tampered_signature.token.json' --idempotency-key 'approve-N3d2_webauthn_tampered_signature' --json`

Actual output:

```text
exit=1
{"schema_version":1,"protocol_version":1,"command":"showcase.approve","ok":false,"complete":false,"data":{},"diagnostics":[{"code":"showcase.trusted_user_confirmation_required","severity":"error","message":"User approval token rejected: WEBAUTHN_BAD_SIGNATURE (webauthn signature for credential_id webauthn-trusted did not verify)","source_path":null,"json_pointer":null,"entity_id":null,"related_ids":[]}],"context":{"workspace_root":"/Users/admin/repos/use-case-matrix-g2-attack","data_root":"/Users/admin/repos/use-case-matrix-g2-attack","component_id":"use-cases","workspace_snapshot":{"repository_id":"unknown","vcs":"unknown","head_revision":"unknown","dirty":false,"working_tree_digest":"sha256:0000000000000000000000000000000000000000000000000000000000000000","component_id":"use-cases","captured_at":"1970-01-01T00:00:00.000Z"}}}
```

Verdict: PASS - attack was blocked/fail-closed.

### PASS - N3e_webauthn_unpinned_credential: N3e WebAuthn credential not pinned

Attack: Use a credential_id not present in the pinned approval_trust.

Expected: showcase.approval_trust_anchor_unpinned or WEBAUTHN_CREDENTIAL_UNKNOWN

Prep commands:

- `node packages/cli/dist/index.js showcase start --repo '/tmp/uc-tiers-acceptance/workspace' --adhoc --select 'tiers.approval.happy_path' --idempotency-key 'start-N3e_webauthn_unpinned_credential' --json`
- `node packages/cli/dist/index.js showcase record-observation --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_n3e_webauthn_unpinned_credential' --item 'item.tiers.approval.happy_path' --text 'Observation for N3e_webauthn_unpinned_credential: behavior matched.' --idempotency-key 'observe-N3e_webauthn_unpinned_credential' --json`
- `node packages/cli/dist/index.js showcase record-verdict --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_n3e_webauthn_unpinned_credential' --item 'item.tiers.approval.happy_path' --verdict pass --idempotency-key 'verdict-N3e_webauthn_unpinned_credential' --json`
- `node packages/cli/dist/index.js showcase finish --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_n3e_webauthn_unpinned_credential' --idempotency-key 'finish-N3e_webauthn_unpinned_credential' --json`
- `node packages/cli/dist/index.js showcase request-approval --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_n3e_webauthn_unpinned_credential' --json > '/tmp/uc-tiers-acceptance/outputs/N3e_webauthn_unpinned_credential.request.json'`
- `node packages/cli/dist/index.js approve-run --request '/tmp/uc-tiers-acceptance/outputs/N3e_webauthn_unpinned_credential.request.json' --webauthn-assertion '/tmp/uc-tiers-acceptance/outputs/N3e_webauthn_unpinned_credential.assertion.json' --decision 'approved' --out '/tmp/uc-tiers-acceptance/outputs/N3e_webauthn_unpinned_credential.token.json' --json`

Attack command: `node packages/cli/dist/index.js showcase approve --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_n3e_webauthn_unpinned_credential' --statement 'Attack N3e_webauthn_unpinned_credential' --approval-token '/tmp/uc-tiers-acceptance/outputs/N3e_webauthn_unpinned_credential.token.json' --idempotency-key 'approve-N3e_webauthn_unpinned_credential' --json`

Actual output:

```text
exit=1
{"schema_version":1,"protocol_version":1,"command":"showcase.approve","ok":false,"complete":false,"data":{},"diagnostics":[{"code":"showcase.approval_trust_anchor_unpinned","severity":"error","message":"approval token signer 'webauthn-rogue' is not in pinned approval_trust.","source_path":null,"json_pointer":null,"entity_id":null,"related_ids":[]}],"context":{"workspace_root":"/Users/admin/repos/use-case-matrix-g2-attack","data_root":"/Users/admin/repos/use-case-matrix-g2-attack","component_id":"use-cases","workspace_snapshot":{"repository_id":"unknown","vcs":"unknown","head_revision":"unknown","dirty":false,"working_tree_digest":"sha256:0000000000000000000000000000000000000000000000000000000000000000","component_id":"use-cases","captured_at":"1970-01-01T00:00:00.000Z"}}}
```

Verdict: PASS - attack was blocked/fail-closed.

### PASS - N4a_tamper_assurance_method: N4 method tamper

Attack: Edit a valid signed token's assurance_method from os_presence to same_channel.

Expected: Rejected/fail-closed: signed body is tamper-evident (BAD_SIGNATURE).

Prep commands:

- `node packages/cli/dist/index.js showcase start --repo '/tmp/uc-tiers-acceptance/workspace' --adhoc --select 'tiers.approval.happy_path' --idempotency-key 'start-N4a_tamper_assurance_method' --json`
- `node packages/cli/dist/index.js showcase record-observation --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_n4a_tamper_assurance_method' --item 'item.tiers.approval.happy_path' --text 'Observation for N4a_tamper_assurance_method: behavior matched.' --idempotency-key 'observe-N4a_tamper_assurance_method' --json`
- `node packages/cli/dist/index.js showcase record-verdict --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_n4a_tamper_assurance_method' --item 'item.tiers.approval.happy_path' --verdict pass --idempotency-key 'verdict-N4a_tamper_assurance_method' --json`
- `node packages/cli/dist/index.js showcase finish --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_n4a_tamper_assurance_method' --idempotency-key 'finish-N4a_tamper_assurance_method' --json`
- `node packages/cli/dist/index.js showcase request-approval --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_n4a_tamper_assurance_method' --json > '/tmp/uc-tiers-acceptance/outputs/N4a_tamper_assurance_method.request.json'`
- `node packages/cli/dist/index.js approve-run --request '/tmp/uc-tiers-acceptance/outputs/N4a_tamper_assurance_method.request.json' --key-file '/tmp/uc-tiers-acceptance/keys/trusted/ci-signing-key.pem' --key-id 'trusted-host' --decision 'approved' --assurance-method 'os_presence' --out '/tmp/uc-tiers-acceptance/outputs/N4a_tamper_assurance_method.token.json' --json`

Attack command: `node packages/cli/dist/index.js showcase approve --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_n4a_tamper_assurance_method' --statement 'Attack N4a_tamper_assurance_method' --approval-token '/tmp/uc-tiers-acceptance/outputs/N4a_tamper_assurance_method.tampered-token.json' --idempotency-key 'approve-N4a_tamper_assurance_method' --json`

Actual output:

```text
exit=1
{"schema_version":1,"protocol_version":1,"command":"showcase.approve","ok":false,"complete":false,"data":{},"diagnostics":[{"code":"showcase.trusted_user_confirmation_required","severity":"error","message":"User approval token rejected: BAD_SIGNATURE (signature for key_id trusted-host did not verify)","source_path":null,"json_pointer":null,"entity_id":null,"related_ids":[]}],"context":{"workspace_root":"/Users/admin/repos/use-case-matrix-g2-attack","data_root":"/Users/admin/repos/use-case-matrix-g2-attack","component_id":"use-cases","workspace_snapshot":{"repository_id":"unknown","vcs":"unknown","head_revision":"unknown","dirty":false,"working_tree_digest":"sha256:0000000000000000000000000000000000000000000000000000000000000000","component_id":"use-cases","captured_at":"1970-01-01T00:00:00.000Z"}}}
```

Verdict: PASS - attack was blocked/fail-closed.

### PASS - N4b_tamper_assurance_tier: N4 tier bump tamper

Attack: Edit a valid signed same_channel token's assurance_tier up to trusted_host_user_presence.

Expected: Rejected/fail-closed: signed body is tamper-evident (BAD_SIGNATURE).

Prep commands:

- `node packages/cli/dist/index.js showcase start --repo '/tmp/uc-tiers-acceptance/workspace' --adhoc --select 'tiers.approval.happy_path' --idempotency-key 'start-N4b_tamper_assurance_tier' --json`
- `node packages/cli/dist/index.js showcase record-observation --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_n4b_tamper_assurance_tier' --item 'item.tiers.approval.happy_path' --text 'Observation for N4b_tamper_assurance_tier: behavior matched.' --idempotency-key 'observe-N4b_tamper_assurance_tier' --json`
- `node packages/cli/dist/index.js showcase record-verdict --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_n4b_tamper_assurance_tier' --item 'item.tiers.approval.happy_path' --verdict pass --idempotency-key 'verdict-N4b_tamper_assurance_tier' --json`
- `node packages/cli/dist/index.js showcase finish --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_n4b_tamper_assurance_tier' --idempotency-key 'finish-N4b_tamper_assurance_tier' --json`
- `node packages/cli/dist/index.js showcase request-approval --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_n4b_tamper_assurance_tier' --json > '/tmp/uc-tiers-acceptance/outputs/N4b_tamper_assurance_tier.request.json'`
- `node packages/cli/dist/index.js approve-run --request '/tmp/uc-tiers-acceptance/outputs/N4b_tamper_assurance_tier.request.json' --key-file '/tmp/uc-tiers-acceptance/keys/trusted/ci-signing-key.pem' --key-id 'trusted-host' --decision 'approved' --assurance-method 'same_channel' --out '/tmp/uc-tiers-acceptance/outputs/N4b_tamper_assurance_tier.token.json' --json`

Attack command: `node packages/cli/dist/index.js showcase approve --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_n4b_tamper_assurance_tier' --statement 'Attack N4b_tamper_assurance_tier' --approval-token '/tmp/uc-tiers-acceptance/outputs/N4b_tamper_assurance_tier.tampered-token.json' --idempotency-key 'approve-N4b_tamper_assurance_tier' --json`

Actual output:

```text
exit=1
{"schema_version":1,"protocol_version":1,"command":"showcase.approve","ok":false,"complete":false,"data":{},"diagnostics":[{"code":"showcase.trusted_user_confirmation_required","severity":"error","message":"User approval token rejected: BAD_SIGNATURE (signature for key_id trusted-host did not verify)","source_path":null,"json_pointer":null,"entity_id":null,"related_ids":[]}],"context":{"workspace_root":"/Users/admin/repos/use-case-matrix-g2-attack","data_root":"/Users/admin/repos/use-case-matrix-g2-attack","component_id":"use-cases","workspace_snapshot":{"repository_id":"unknown","vcs":"unknown","head_revision":"unknown","dirty":false,"working_tree_digest":"sha256:0000000000000000000000000000000000000000000000000000000000000000","component_id":"use-cases","captured_at":"1970-01-01T00:00:00.000Z"}}}
```

Verdict: PASS - attack was blocked/fail-closed.

### PASS - N5_webauthn_replay_different_run: N5 WebAuthn replay across run

Attack: Mint a valid WebAuthn assertion/token for run A and submit it to run B.

Expected: Rejected/fail-closed: challenge is bound to the live run binding.

Prep commands:

- `node packages/cli/dist/index.js showcase start --repo '/tmp/uc-tiers-acceptance/workspace' --adhoc --select 'tiers.approval.happy_path' --idempotency-key 'start-N5_webauthn_replay_different_run_A' --json`
- `node packages/cli/dist/index.js showcase record-observation --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_n5_webauthn_replay_different_run_a' --item 'item.tiers.approval.happy_path' --text 'Observation for N5_webauthn_replay_different_run_A: behavior matched.' --idempotency-key 'observe-N5_webauthn_replay_different_run_A' --json`
- `node packages/cli/dist/index.js showcase record-verdict --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_n5_webauthn_replay_different_run_a' --item 'item.tiers.approval.happy_path' --verdict pass --idempotency-key 'verdict-N5_webauthn_replay_different_run_A' --json`
- `node packages/cli/dist/index.js showcase finish --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_n5_webauthn_replay_different_run_a' --idempotency-key 'finish-N5_webauthn_replay_different_run_A' --json`
- `node packages/cli/dist/index.js showcase request-approval --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_n5_webauthn_replay_different_run_a' --json > '/tmp/uc-tiers-acceptance/outputs/N5_webauthn_replay_different_run_A.request.json'`
- `node packages/cli/dist/index.js approve-run --request '/tmp/uc-tiers-acceptance/outputs/N5_webauthn_replay_different_run_A.request.json' --webauthn-assertion '/tmp/uc-tiers-acceptance/outputs/N5_webauthn_replay_different_run.assertion.json' --decision 'approved' --out '/tmp/uc-tiers-acceptance/outputs/N5_webauthn_replay_different_run.token.json' --json`
- `node packages/cli/dist/index.js showcase start --repo '/tmp/uc-tiers-acceptance/workspace' --adhoc --select 'tiers.approval.happy_path' --idempotency-key 'start-N5_webauthn_replay_different_run_B' --json`
- `node packages/cli/dist/index.js showcase record-observation --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_n5_webauthn_replay_different_run_b' --item 'item.tiers.approval.happy_path' --text 'Observation for N5_webauthn_replay_different_run_B: behavior matched.' --idempotency-key 'observe-N5_webauthn_replay_different_run_B' --json`
- `node packages/cli/dist/index.js showcase record-verdict --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_n5_webauthn_replay_different_run_b' --item 'item.tiers.approval.happy_path' --verdict pass --idempotency-key 'verdict-N5_webauthn_replay_different_run_B' --json`
- `node packages/cli/dist/index.js showcase finish --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_n5_webauthn_replay_different_run_b' --idempotency-key 'finish-N5_webauthn_replay_different_run_B' --json`

Attack command: `node packages/cli/dist/index.js showcase approve --repo '/tmp/uc-tiers-acceptance/workspace' --run 'run.start_n5_webauthn_replay_different_run_b' --statement 'Attack N5_webauthn_replay_different_run' --approval-token '/tmp/uc-tiers-acceptance/outputs/N5_webauthn_replay_different_run.token.json' --idempotency-key 'approve-N5_webauthn_replay_different_run' --json`

Actual output:

```text
exit=1
{"schema_version":1,"protocol_version":1,"command":"showcase.approve","ok":false,"complete":false,"data":{},"diagnostics":[{"code":"showcase.trusted_user_confirmation_required","severity":"error","message":"User approval token rejected: WEBAUTHN_CHALLENGE_MISMATCH (webauthn clientDataJSON.challenge does not match this approval binding)","source_path":null,"json_pointer":null,"entity_id":null,"related_ids":[]}],"context":{"workspace_root":"/Users/admin/repos/use-case-matrix-g2-attack","data_root":"/Users/admin/repos/use-case-matrix-g2-attack","component_id":"use-cases","workspace_snapshot":{"repository_id":"unknown","vcs":"unknown","head_revision":"unknown","dirty":false,"working_tree_digest":"sha256:0000000000000000000000000000000000000000000000000000000000000000","component_id":"use-cases","captured_at":"1970-01-01T00:00:00.000Z"}}}
```

Verdict: PASS - attack was blocked/fail-closed.

## Additional Bypass Sweep

- Tried both caller-nominated trust-root forms for X1/N1: `--keyring` and `--public-key`; both were blocked by pinned `approval_trust` before signature trust could be introduced.
- Split WebAuthn tampering into separate authenticator-data and signature probes; both failed closed with `WEBAUTHN_BAD_SIGNATURE`.
- The unpinned WebAuthn credential was blocked at the pinned-anchor guard (`showcase.approval_trust_anchor_unpinned`), which is earlier than the core credential resolver and still fail-closed.

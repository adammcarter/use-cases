# 0.3.0 Higher-Assurance Approval Tiers Live Acceptance

Scratch root: `/tmp/uc-tiers-live-9YfGbp`
Repo worktree: `/Users/admin/repos/use-case-matrix-g2-happy`
Built CLI: `node packages/cli/dist/index.js`
Date: 2026-07-05T11:28:41.541Z

No product code was modified. Scratch workspaces and key material were created under `/tmp/uc-tiers-live-9YfGbp` only.

## Summary

| Variant | Result | Finding |
|---|---:|---|
| T1 | PASS | Regression happy path still approves ed25519 token |
| T2a | PASS | Pinned approval_trust verifies without caller keyring |
| T2b | PASS | --keyring narrows pinned approval_trust to selected subset |
| T2c | PASS | Unpinned caller-supplied trust emits advisory diagnostic |
| T3-automation | PASS | Assurance method automation records tier untrusted_automation |
| T3-same_channel | PASS | Assurance method same_channel records tier same_channel_operator_confirmation |
| T3-os_presence | PASS | Assurance method os_presence records tier trusted_host_user_presence |
| T4 | PASS | WebAuthn assertion records webauthn_hardware tier |
| T5 | PASS | Signed rejection records verified actor and tier |
| T6 | PASS | Policy floor webauthn_hardware accepts hardware and rejects lower tier |

## Setup

Schema shapes read:

- keyring.schema.json: new key entries use max_assurance_tier; ed25519 caps stop at trusted_host_user_presence; WebAuthn entries require credential_id, credential_public_key_alg, credential_public_key_spki, and max_assurance_tier webauthn_hardware.
- workspace-config.schema.json: approval_trust may pin keyring_path, inline keyring, or public_keys; caller flags may narrow but not introduce roots once pinned.
- approval-token.schema.json: tokens can carry assurance_method/assurance_tier, and WebAuthn signatures carry credential_id, authenticator_data, client_data_json, signature.

Command: `pnpm -r build`
Exit: 0
Stdout:
```text
Scope: 3 of 4 workspace projects
packages/core build$ tsc -b
packages/core build: Done
packages/cli build$ tsc -b
packages/mcp build$ tsc -b
packages/cli build: Done
packages/mcp build: Done
```

Command: `node packages/cli/dist/index.js keygen --repo /tmp/uc-tiers-live-9YfGbp/keygen-workspace --out /tmp/uc-tiers-live-9YfGbp/keys-human --json`
Exit: 0
Stdout:
```text
{"schema_version":1,"protocol_version":1,"command":"markers.keygen","ok":true,"complete":true,"data":{"algorithm":"ed25519","private_key_path":"/tmp/uc-tiers-live-9YfGbp/keys-human/ci-signing-key.pem","public_key_path":"/tmp/uc-tiers-live-9YfGbp/keys-human/ci-signing-key.pub.pem","public_key":"-----BEGIN PUBLIC KEY-----\nMCowBQYDK2VwAyEAZ9fS+GAp0trO2lM/VjPkwqItlrTMmmKZ1+a5nJ9Vu2U=\n-----END PUBLIC KEY-----\n","warning":"The private key is a CI secret: store it ONLY in your CI secret store (never commit it, never write it into the repo). Commit / distribute only the public key."},"diagnostics":[],"context":{"workspace_root":"/tmp/uc-tiers-live-9YfGbp/keygen-workspace","data_root":"/tmp/uc-tiers-live-9YfGbp/keygen-workspace","component_id":"use-cases","workspace_snapshot":{"repository_id":"unknown","vcs":"unknown","head_revision":"unknown","dirty":false,"working_tree_digest":"sha256:0000000000000000000000000000000000000000000000000000000000000000","component_id":"use-cases","captured_at":"1970-01-01T00:00:00.000Z"}}}
```

Command: `node packages/cli/dist/index.js keygen --repo /tmp/uc-tiers-live-9YfGbp/keygen-workspace --out /tmp/uc-tiers-live-9YfGbp/keys-operator --json`
Exit: 0
Stdout:
```text
{"schema_version":1,"protocol_version":1,"command":"markers.keygen","ok":true,"complete":true,"data":{"algorithm":"ed25519","private_key_path":"/tmp/uc-tiers-live-9YfGbp/keys-operator/ci-signing-key.pem","public_key_path":"/tmp/uc-tiers-live-9YfGbp/keys-operator/ci-signing-key.pub.pem","public_key":"-----BEGIN PUBLIC KEY-----\nMCowBQYDK2VwAyEAOLt4iHctMp01vJamdVjR5bZbLRqec7bacdMSV1VDEB0=\n-----END PUBLIC KEY-----\n","warning":"The private key is a CI secret: store it ONLY in your CI secret store (never commit it, never write it into the repo). Commit / distribute only the public key."},"diagnostics":[],"context":{"workspace_root":"/tmp/uc-tiers-live-9YfGbp/keygen-workspace","data_root":"/tmp/uc-tiers-live-9YfGbp/keygen-workspace","component_id":"use-cases","workspace_snapshot":{"repository_id":"unknown","vcs":"unknown","head_revision":"unknown","dirty":false,"working_tree_digest":"sha256:0000000000000000000000000000000000000000000000000000000000000000","component_id":"use-cases","captured_at":"1970-01-01T00:00:00.000Z"}}}
```

## T1. Regression happy path still approves ed25519 token

Expected: Finished run can request approval; approve-run signs with ed25519; showcase approve verifies via --keyring; status is approved with trusted_host_user_presence.

Actual:

Finished-run preparation commands:
- `node packages/cli/dist/index.js showcase start --repo /tmp/uc-tiers-live-9YfGbp/t1-regression --adhoc --select showcase.live.golden --json --idempotency-key t1-start` -> exit 0
- `node packages/cli/dist/index.js showcase record-observation --repo /tmp/uc-tiers-live-9YfGbp/t1-regression --run run.t1_start --item item.showcase.live.golden --text 'The live behaviour matched the expected outcome.' --json --idempotency-key t1-observe` -> exit 0
- `node packages/cli/dist/index.js showcase record-verdict --repo /tmp/uc-tiers-live-9YfGbp/t1-regression --run run.t1_start --item item.showcase.live.golden --verdict pass --actor agent --json --idempotency-key t1-verdict` -> exit 0
- `node packages/cli/dist/index.js showcase finish --repo /tmp/uc-tiers-live-9YfGbp/t1-regression --run run.t1_start --json --idempotency-key t1-finish` -> exit 0

Command: `node packages/cli/dist/index.js showcase status --repo /tmp/uc-tiers-live-9YfGbp/t1-regression --run run.t1_start`
Exit: 0
Stdout:
```text
showcase run.t1_start: completed · passed
approval: pending

Add --json for the full machine-readable result envelope.
```

Command: `node packages/cli/dist/index.js showcase request-approval --repo /tmp/uc-tiers-live-9YfGbp/t1-regression --run run.t1_start --json`
Exit: 0
Stdout:
```text
{"approval_request_schema":"ucase-approval-request-v1","binding":{"run_id":"run.t1_start","finish_event_id":"evt.run.t1_start.4","plan_content_hash":"sha256:0dab557731519d4aa11efd2408f9b22d98a548156afcba594b9cf6a37d573ec0","ledger_head_hash":"sha256:c7de63ac15f388a2e676fe38be6e02880c9b827ee056603272899e9372cc8cc5","evidence_digest":"sha256:403d55992d8ee495b2a9296af434a203641e81e667f5f4ade26e69c31771cf89","git_commit":"unknown","ci_freshness_digest":"sha256:6482de42ede6fa7313428ceb6d1d068967e01232c6d24e8254fa80bd85ccc1f8"},"jti":"approval.466fbf33-cf86-47e3-bcdc-bb9d97cd3a05","iat":"2026-07-05T11:28:14.235Z","exp":"2026-07-05T11:43:14.235Z"}
```

Command: `node packages/cli/dist/index.js approve-run --request /tmp/uc-tiers-live-9YfGbp/t1-request.json --key-file /tmp/uc-tiers-live-9YfGbp/keys-human/ci-signing-key.pem --key-id human-key-1 --out /tmp/uc-tiers-live-9YfGbp/t1-token.json`
Exit: 0
Stdout:
```text
✓ showcase.approve_run
  approval_token_path: /tmp/uc-tiers-live-9YfGbp/t1-token.json
  jti: approval.466fbf33-cf86-47e3-bcdc-bb9d97cd3a05
  decision: approved
  key_id: human-key-1
  assurance_method: os_presence
  assurance_tier: trusted_host_user_presence

Add --json for the full machine-readable result envelope.
```

Command: `node packages/cli/dist/index.js showcase approve --repo /tmp/uc-tiers-live-9YfGbp/t1-regression --run run.t1_start --statement 'Genuine human sign-off.' --approval-token /tmp/uc-tiers-live-9YfGbp/t1-token.json --keyring /tmp/uc-tiers-live-9YfGbp/t1-regression/keyring.json --json`
Exit: 0
Stdout summary from JSON envelope:
```text
ok=true
complete=true
run_id=run.t1_start
approval_state=approved
run_outcome=passed
approval_actor=user
approval_tier=trusted_host_user_presence
diagnostics=warning:showcase.approval_trust_anchor_caller_supplied: Approval-token verification is using caller-supplied trust material because use-cases.yml has no approval_trust pin.
```

Command: `node packages/cli/dist/index.js showcase status --repo /tmp/uc-tiers-live-9YfGbp/t1-regression --run run.t1_start --keyring /tmp/uc-tiers-live-9YfGbp/t1-regression/keyring.json`
Exit: 0
Stdout:
```text
showcase run.t1_start: completed · passed
approval: approved
approved by user · tier trusted_host_user_presence

Add --json for the full machine-readable result envelope.
```

Result: PASS

## T2a. Pinned approval_trust verifies without caller keyring

Expected: A token signed by a key pinned in use-cases.yml approval_trust verifies and approves with no --keyring flag.

Actual:

Finished-run preparation commands:
- `node packages/cli/dist/index.js showcase start --repo /tmp/uc-tiers-live-9YfGbp/t2a-pinned --adhoc --select showcase.live.golden --json --idempotency-key t2a-start` -> exit 0
- `node packages/cli/dist/index.js showcase record-observation --repo /tmp/uc-tiers-live-9YfGbp/t2a-pinned --run run.t2a_start --item item.showcase.live.golden --text 'The live behaviour matched the expected outcome.' --json --idempotency-key t2a-observe` -> exit 0
- `node packages/cli/dist/index.js showcase record-verdict --repo /tmp/uc-tiers-live-9YfGbp/t2a-pinned --run run.t2a_start --item item.showcase.live.golden --verdict pass --actor agent --json --idempotency-key t2a-verdict` -> exit 0
- `node packages/cli/dist/index.js showcase finish --repo /tmp/uc-tiers-live-9YfGbp/t2a-pinned --run run.t2a_start --json --idempotency-key t2a-finish` -> exit 0

Command: `node packages/cli/dist/index.js showcase status --repo /tmp/uc-tiers-live-9YfGbp/t2a-pinned --run run.t2a_start`
Exit: 0
Stdout:
```text
showcase run.t2a_start: completed · passed
approval: pending

Add --json for the full machine-readable result envelope.
```

Command: `node packages/cli/dist/index.js showcase request-approval --repo /tmp/uc-tiers-live-9YfGbp/t2a-pinned --run run.t2a_start --json`
Exit: 0
Stdout:
```text
{"approval_request_schema":"ucase-approval-request-v1","binding":{"run_id":"run.t2a_start","finish_event_id":"evt.run.t2a_start.4","plan_content_hash":"sha256:0dab557731519d4aa11efd2408f9b22d98a548156afcba594b9cf6a37d573ec0","ledger_head_hash":"sha256:988f690f5b4e57a0c23cdcbb8adc4d5a9cb77144c25878cf160eac6397bc14c7","evidence_digest":"sha256:11e097d1b72be5cb32532cc2f040fc8e7f06f6a9d84147ed57549b80e378307d","git_commit":"unknown","ci_freshness_digest":"sha256:83c63dcfa30c9a36b4fa10548243e2bacc5b181d27d92a12115c032b8cc88f89"},"jti":"approval.0f4f2498-8a97-4dc0-9a11-8ec602966da6","iat":"2026-07-05T11:28:16.902Z","exp":"2026-07-05T11:43:16.902Z"}
```

Command: `node packages/cli/dist/index.js approve-run --request /tmp/uc-tiers-live-9YfGbp/t2a-request.json --key-file /tmp/uc-tiers-live-9YfGbp/keys-human/ci-signing-key.pem --key-id human-key-1 --out /tmp/uc-tiers-live-9YfGbp/t2a-token.json`
Exit: 0
Stdout:
```text
✓ showcase.approve_run
  approval_token_path: /tmp/uc-tiers-live-9YfGbp/t2a-token.json
  jti: approval.0f4f2498-8a97-4dc0-9a11-8ec602966da6
  decision: approved
  key_id: human-key-1
  assurance_method: os_presence
  assurance_tier: trusted_host_user_presence

Add --json for the full machine-readable result envelope.
```

Command: `node packages/cli/dist/index.js showcase approve --repo /tmp/uc-tiers-live-9YfGbp/t2a-pinned --run run.t2a_start --statement 'Pinned workspace trust anchor verified this sign-off.' --approval-token /tmp/uc-tiers-live-9YfGbp/t2a-token.json --json`
Exit: 0
Stdout summary from JSON envelope:
```text
ok=true
complete=true
run_id=run.t2a_start
approval_state=approved
run_outcome=passed
approval_actor=user
approval_tier=trusted_host_user_presence
diagnostics=(none)
```

Command: `node packages/cli/dist/index.js showcase status --repo /tmp/uc-tiers-live-9YfGbp/t2a-pinned --run run.t2a_start`
Exit: 0
Stdout:
```text
showcase run.t2a_start: completed · passed
approval: approved
approved by user · tier trusted_host_user_presence

Add --json for the full machine-readable result envelope.
```

Result: PASS

## T2b. --keyring narrows pinned approval_trust to selected subset

Expected: Workspace pins human+operator keys; caller passes a keyring containing only the pinned operator key; operator-signed token verifies and status is approved.

Actual:

Finished-run preparation commands:
- `node packages/cli/dist/index.js showcase start --repo /tmp/uc-tiers-live-9YfGbp/t2b-narrow --adhoc --select showcase.live.golden --json --idempotency-key t2b-start` -> exit 0
- `node packages/cli/dist/index.js showcase record-observation --repo /tmp/uc-tiers-live-9YfGbp/t2b-narrow --run run.t2b_start --item item.showcase.live.golden --text 'The live behaviour matched the expected outcome.' --json --idempotency-key t2b-observe` -> exit 0
- `node packages/cli/dist/index.js showcase record-verdict --repo /tmp/uc-tiers-live-9YfGbp/t2b-narrow --run run.t2b_start --item item.showcase.live.golden --verdict pass --actor agent --json --idempotency-key t2b-verdict` -> exit 0
- `node packages/cli/dist/index.js showcase finish --repo /tmp/uc-tiers-live-9YfGbp/t2b-narrow --run run.t2b_start --json --idempotency-key t2b-finish` -> exit 0

Command: `node packages/cli/dist/index.js showcase status --repo /tmp/uc-tiers-live-9YfGbp/t2b-narrow --run run.t2b_start`
Exit: 0
Stdout:
```text
showcase run.t2b_start: completed · passed
approval: pending

Add --json for the full machine-readable result envelope.
```

Command: `node packages/cli/dist/index.js showcase request-approval --repo /tmp/uc-tiers-live-9YfGbp/t2b-narrow --run run.t2b_start --json`
Exit: 0
Stdout:
```text
{"approval_request_schema":"ucase-approval-request-v1","binding":{"run_id":"run.t2b_start","finish_event_id":"evt.run.t2b_start.4","plan_content_hash":"sha256:0dab557731519d4aa11efd2408f9b22d98a548156afcba594b9cf6a37d573ec0","ledger_head_hash":"sha256:7737ff5d584e83c14d078659abdfba8493bad8000423159fad5f21272f232a9f","evidence_digest":"sha256:ef385449ff0d10b6f29616cc1b6029ad6f47176b1fae9a0419498d400781c91c","git_commit":"unknown","ci_freshness_digest":"sha256:65a167c0c9071b8e1a2ee03d246ed207b7827c3bd3483b33f3b1603cea72c552"},"jti":"approval.f34a10f0-6964-4d6c-8710-642a74c690f1","iat":"2026-07-05T11:28:19.866Z","exp":"2026-07-05T11:43:19.866Z"}
```

Command: `node packages/cli/dist/index.js approve-run --request /tmp/uc-tiers-live-9YfGbp/t2b-request.json --key-file /tmp/uc-tiers-live-9YfGbp/keys-operator/ci-signing-key.pem --key-id operator-key-1 --out /tmp/uc-tiers-live-9YfGbp/t2b-token.json`
Exit: 0
Stdout:
```text
✓ showcase.approve_run
  approval_token_path: /tmp/uc-tiers-live-9YfGbp/t2b-token.json
  jti: approval.f34a10f0-6964-4d6c-8710-642a74c690f1
  decision: approved
  key_id: operator-key-1
  assurance_method: os_presence
  assurance_tier: trusted_host_user_presence

Add --json for the full machine-readable result envelope.
```

Command: `node packages/cli/dist/index.js showcase approve --repo /tmp/uc-tiers-live-9YfGbp/t2b-narrow --run run.t2b_start --statement 'Caller selected a pinned subset.' --approval-token /tmp/uc-tiers-live-9YfGbp/t2b-token.json --keyring /tmp/uc-tiers-live-9YfGbp/t2b-narrow/operator-only-keyring.json --json`
Exit: 0
Stdout summary from JSON envelope:
```text
ok=true
complete=true
run_id=run.t2b_start
approval_state=approved
run_outcome=passed
approval_actor=user
approval_tier=trusted_host_user_presence
diagnostics=(none)
```

Command: `node packages/cli/dist/index.js showcase status --repo /tmp/uc-tiers-live-9YfGbp/t2b-narrow --run run.t2b_start --keyring /tmp/uc-tiers-live-9YfGbp/t2b-narrow/operator-only-keyring.json`
Exit: 0
Stdout:
```text
showcase run.t2b_start: completed · passed
approval: approved
approved by user · tier trusted_host_user_presence

Add --json for the full machine-readable result envelope.
```

Result: PASS

## T2c. Unpinned caller-supplied trust emits advisory diagnostic

Expected: When use-cases.yml has no approval_trust pin, caller-supplied --keyring still verifies but emits approval_trust_anchor_caller_supplied.

Actual:

Finished-run preparation commands:
- `node packages/cli/dist/index.js showcase start --repo /tmp/uc-tiers-live-9YfGbp/t2c-unpinned --adhoc --select showcase.live.golden --json --idempotency-key t2c-start` -> exit 0
- `node packages/cli/dist/index.js showcase record-observation --repo /tmp/uc-tiers-live-9YfGbp/t2c-unpinned --run run.t2c_start --item item.showcase.live.golden --text 'The live behaviour matched the expected outcome.' --json --idempotency-key t2c-observe` -> exit 0
- `node packages/cli/dist/index.js showcase record-verdict --repo /tmp/uc-tiers-live-9YfGbp/t2c-unpinned --run run.t2c_start --item item.showcase.live.golden --verdict pass --actor agent --json --idempotency-key t2c-verdict` -> exit 0
- `node packages/cli/dist/index.js showcase finish --repo /tmp/uc-tiers-live-9YfGbp/t2c-unpinned --run run.t2c_start --json --idempotency-key t2c-finish` -> exit 0

Command: `node packages/cli/dist/index.js showcase status --repo /tmp/uc-tiers-live-9YfGbp/t2c-unpinned --run run.t2c_start`
Exit: 0
Stdout:
```text
showcase run.t2c_start: completed · passed
approval: pending

Add --json for the full machine-readable result envelope.
```

Command: `node packages/cli/dist/index.js showcase request-approval --repo /tmp/uc-tiers-live-9YfGbp/t2c-unpinned --run run.t2c_start --json`
Exit: 0
Stdout:
```text
{"approval_request_schema":"ucase-approval-request-v1","binding":{"run_id":"run.t2c_start","finish_event_id":"evt.run.t2c_start.4","plan_content_hash":"sha256:0dab557731519d4aa11efd2408f9b22d98a548156afcba594b9cf6a37d573ec0","ledger_head_hash":"sha256:f96b9059c98e60e723533d4d59e038f56a031e5444a2e440d10b08dd48dea74a","evidence_digest":"sha256:eac6ca00c620a79a15ef45497f64e5f5461f1c2acb1602bbb3f9741b9b21637f","git_commit":"unknown","ci_freshness_digest":"sha256:8fa6df9013ca57b0c1f8168198f0949b367a32348f526d4d06b025c8b3a87d62"},"jti":"approval.d75d1712-aece-4bb7-bc83-7a5525c858d9","iat":"2026-07-05T11:28:22.440Z","exp":"2026-07-05T11:43:22.440Z"}
```

Command: `node packages/cli/dist/index.js approve-run --request /tmp/uc-tiers-live-9YfGbp/t2c-request.json --key-file /tmp/uc-tiers-live-9YfGbp/keys-human/ci-signing-key.pem --key-id human-key-1 --out /tmp/uc-tiers-live-9YfGbp/t2c-token.json`
Exit: 0
Stdout:
```text
✓ showcase.approve_run
  approval_token_path: /tmp/uc-tiers-live-9YfGbp/t2c-token.json
  jti: approval.d75d1712-aece-4bb7-bc83-7a5525c858d9
  decision: approved
  key_id: human-key-1
  assurance_method: os_presence
  assurance_tier: trusted_host_user_presence

Add --json for the full machine-readable result envelope.
```

Command: `node packages/cli/dist/index.js showcase approve --repo /tmp/uc-tiers-live-9YfGbp/t2c-unpinned --run run.t2c_start --statement 'Caller supplied trust material.' --approval-token /tmp/uc-tiers-live-9YfGbp/t2c-token.json --keyring /tmp/uc-tiers-live-9YfGbp/t2c-unpinned/keyring.json --json`
Exit: 0
Stdout summary from JSON envelope:
```text
ok=true
complete=true
run_id=run.t2c_start
approval_state=approved
run_outcome=passed
approval_actor=user
approval_tier=trusted_host_user_presence
diagnostics=warning:showcase.approval_trust_anchor_caller_supplied: Approval-token verification is using caller-supplied trust material because use-cases.yml has no approval_trust pin.
```

Command: `node packages/cli/dist/index.js showcase status --repo /tmp/uc-tiers-live-9YfGbp/t2c-unpinned --run run.t2c_start --keyring /tmp/uc-tiers-live-9YfGbp/t2c-unpinned/keyring.json --json`
Exit: 0
Stdout:
```text
{"schema_version":1,"protocol_version":1,"command":"showcase.status","ok":true,"complete":true,"data":{"schema_version":1,"run_id":"run.t2c_start","complete":true,"execution_status":"completed","run_outcome":"passed","approval_state":"approved","unresolved_failure_count":0,"approval":{"actor_type":"user","assurance_tier":"trusted_host_user_presence"},"items":[{"plan_item_id":"item.showcase.live.golden","verdict":"pass","item_currency":"current","verification_state":"requirements_met","latest_observation_event_id":"evt.run.t2c_start.2","latest_verdict_event_id":"evt.run.t2c_start.3"}],"known_gaps":[],"diagnostic_summary":{}},"diagnostics":[{"code":"showcase.approval_trust_anchor_caller_supplied","severity":"warning","message":"Approval-token verification is using caller-supplied trust material because use-cases.yml has no approval_trust pin.","source_path":null,"json_pointer":null,"entity_id":null,"related_ids":[]}],"context":{"workspace_root":"/private/tmp/uc-tiers-live-9YfGbp/t2c-unpinned","data_root":"/private/tmp/uc-tiers-live-9YfGbp/t2c-unpinned","component_id":"presentation-skills","workspace_snapshot":{"repository_id":"unknown","vcs":"unknown","head_revision":"unknown","dirty":false,"working_tree_digest":"sha256:0000000000000000000000000000000000000000000000000000000000000000","component_id":"presentation-skills","captured_at":"1970-01-01T00:00:00.000Z"}}}
```

Result: PASS

## T3-automation. Assurance method automation records tier untrusted_automation

Expected: A key capped at trusted_host_user_presence signs a automation approval; token/status tier is untrusted_automation.

Actual:

Finished-run preparation commands:
- `node packages/cli/dist/index.js showcase start --repo /tmp/uc-tiers-live-9YfGbp/t3-automation --adhoc --select showcase.live.golden --json --idempotency-key t3-automation-start` -> exit 0
- `node packages/cli/dist/index.js showcase record-observation --repo /tmp/uc-tiers-live-9YfGbp/t3-automation --run run.t3_automation_start --item item.showcase.live.golden --text 'The live behaviour matched the expected outcome.' --json --idempotency-key t3-automation-observe` -> exit 0
- `node packages/cli/dist/index.js showcase record-verdict --repo /tmp/uc-tiers-live-9YfGbp/t3-automation --run run.t3_automation_start --item item.showcase.live.golden --verdict pass --actor agent --json --idempotency-key t3-automation-verdict` -> exit 0
- `node packages/cli/dist/index.js showcase finish --repo /tmp/uc-tiers-live-9YfGbp/t3-automation --run run.t3_automation_start --json --idempotency-key t3-automation-finish` -> exit 0

Command: `node packages/cli/dist/index.js showcase status --repo /tmp/uc-tiers-live-9YfGbp/t3-automation --run run.t3_automation_start`
Exit: 0
Stdout:
```text
showcase run.t3_automation_start: completed · passed
approval: pending

Add --json for the full machine-readable result envelope.
```

Command: `node packages/cli/dist/index.js showcase request-approval --repo /tmp/uc-tiers-live-9YfGbp/t3-automation --run run.t3_automation_start --json`
Exit: 0
Stdout:
```text
{"approval_request_schema":"ucase-approval-request-v1","binding":{"run_id":"run.t3_automation_start","finish_event_id":"evt.run.t3_automation_start.4","plan_content_hash":"sha256:31150a70988e8b3bc69c86be1a89e2e3438e36068bd7d17dcf58764c5f2699d4","ledger_head_hash":"sha256:6b30e7f496439dabb637746ce011d55f36ad2ab81a26cb7bcf1b9ea299d0ccf0","evidence_digest":"sha256:2e40b46caefcd93d108f3043205a285c85e1b0a870f30bf447538e7f84cd5eb4","git_commit":"unknown","ci_freshness_digest":"sha256:cab6f85c697033cf72b2d94e892d13f316f494b633816baf801acd2df1cc6934"},"jti":"approval.695dc139-3504-4183-8760-f1940b35805a","iat":"2026-07-05T11:28:24.803Z","exp":"2026-07-05T11:43:24.803Z"}
```

Command: `node packages/cli/dist/index.js approve-run --request /tmp/uc-tiers-live-9YfGbp/t3-automation-request.json --key-file /tmp/uc-tiers-live-9YfGbp/keys-human/ci-signing-key.pem --key-id human-key-1 --out /tmp/uc-tiers-live-9YfGbp/t3-automation-token.json --assurance-method automation`
Exit: 0
Stdout:
```text
✓ showcase.approve_run
  approval_token_path: /tmp/uc-tiers-live-9YfGbp/t3-automation-token.json
  jti: approval.695dc139-3504-4183-8760-f1940b35805a
  decision: approved
  key_id: human-key-1
  assurance_method: automation
  assurance_tier: untrusted_automation

Add --json for the full machine-readable result envelope.
```

Command: `node packages/cli/dist/index.js showcase approve --repo /tmp/uc-tiers-live-9YfGbp/t3-automation --run run.t3_automation_start --statement 'Method automation approval.' --approval-token /tmp/uc-tiers-live-9YfGbp/t3-automation-token.json --keyring /tmp/uc-tiers-live-9YfGbp/t3-automation/keyring.json --json`
Exit: 0
Stdout summary from JSON envelope:
```text
ok=true
complete=true
run_id=run.t3_automation_start
approval_state=approved
run_outcome=passed
approval_actor=user
approval_tier=untrusted_automation
diagnostics=warning:showcase.approval_trust_anchor_caller_supplied: Approval-token verification is using caller-supplied trust material because use-cases.yml has no approval_trust pin.
```

Command: `node packages/cli/dist/index.js showcase status --repo /tmp/uc-tiers-live-9YfGbp/t3-automation --run run.t3_automation_start --keyring /tmp/uc-tiers-live-9YfGbp/t3-automation/keyring.json`
Exit: 0
Stdout:
```text
showcase run.t3_automation_start: completed · passed
approval: approved
approved by user · tier untrusted_automation

Add --json for the full machine-readable result envelope.
```

Result: PASS

## T3-same_channel. Assurance method same_channel records tier same_channel_operator_confirmation

Expected: A key capped at trusted_host_user_presence signs a same_channel approval; token/status tier is same_channel_operator_confirmation.

Actual:

Finished-run preparation commands:
- `node packages/cli/dist/index.js showcase start --repo /tmp/uc-tiers-live-9YfGbp/t3-same_channel --adhoc --select showcase.live.golden --json --idempotency-key t3-same_channel-start` -> exit 0
- `node packages/cli/dist/index.js showcase record-observation --repo /tmp/uc-tiers-live-9YfGbp/t3-same_channel --run run.t3_same_channel_start --item item.showcase.live.golden --text 'The live behaviour matched the expected outcome.' --json --idempotency-key t3-same_channel-observe` -> exit 0
- `node packages/cli/dist/index.js showcase record-verdict --repo /tmp/uc-tiers-live-9YfGbp/t3-same_channel --run run.t3_same_channel_start --item item.showcase.live.golden --verdict pass --actor agent --json --idempotency-key t3-same_channel-verdict` -> exit 0
- `node packages/cli/dist/index.js showcase finish --repo /tmp/uc-tiers-live-9YfGbp/t3-same_channel --run run.t3_same_channel_start --json --idempotency-key t3-same_channel-finish` -> exit 0

Command: `node packages/cli/dist/index.js showcase status --repo /tmp/uc-tiers-live-9YfGbp/t3-same_channel --run run.t3_same_channel_start`
Exit: 0
Stdout:
```text
showcase run.t3_same_channel_start: completed · passed
approval: pending

Add --json for the full machine-readable result envelope.
```

Command: `node packages/cli/dist/index.js showcase request-approval --repo /tmp/uc-tiers-live-9YfGbp/t3-same_channel --run run.t3_same_channel_start --json`
Exit: 0
Stdout:
```text
{"approval_request_schema":"ucase-approval-request-v1","binding":{"run_id":"run.t3_same_channel_start","finish_event_id":"evt.run.t3_same_channel_start.4","plan_content_hash":"sha256:c276d1db48b27545d032f139ac305d6111fac3e86b01b2876b815d185f68aa5a","ledger_head_hash":"sha256:8d200195f1c78201b0a9031453588f18d72396fdbff4b928f15f856d591acfec","evidence_digest":"sha256:cf2c647c548b0434bac144c028447120435ac195efc163a0bd68c10ed16ab6ec","git_commit":"unknown","ci_freshness_digest":"sha256:d0206f340a47c8fb395a32e5663b25b469fc28fd27204fa7cde17c18c22dc65d"},"jti":"approval.1f5cd759-1679-4447-bd07-861f82823f14","iat":"2026-07-05T11:28:27.649Z","exp":"2026-07-05T11:43:27.649Z"}
```

Command: `node packages/cli/dist/index.js approve-run --request /tmp/uc-tiers-live-9YfGbp/t3-same_channel-request.json --key-file /tmp/uc-tiers-live-9YfGbp/keys-human/ci-signing-key.pem --key-id human-key-1 --out /tmp/uc-tiers-live-9YfGbp/t3-same_channel-token.json --assurance-method same_channel`
Exit: 0
Stdout:
```text
✓ showcase.approve_run
  approval_token_path: /tmp/uc-tiers-live-9YfGbp/t3-same_channel-token.json
  jti: approval.1f5cd759-1679-4447-bd07-861f82823f14
  decision: approved
  key_id: human-key-1
  assurance_method: same_channel
  assurance_tier: same_channel_operator_confirmation

Add --json for the full machine-readable result envelope.
```

Command: `node packages/cli/dist/index.js showcase approve --repo /tmp/uc-tiers-live-9YfGbp/t3-same_channel --run run.t3_same_channel_start --statement 'Method same_channel approval.' --approval-token /tmp/uc-tiers-live-9YfGbp/t3-same_channel-token.json --keyring /tmp/uc-tiers-live-9YfGbp/t3-same_channel/keyring.json --json`
Exit: 0
Stdout summary from JSON envelope:
```text
ok=true
complete=true
run_id=run.t3_same_channel_start
approval_state=approved
run_outcome=passed
approval_actor=user
approval_tier=same_channel_operator_confirmation
diagnostics=warning:showcase.approval_trust_anchor_caller_supplied: Approval-token verification is using caller-supplied trust material because use-cases.yml has no approval_trust pin.
```

Command: `node packages/cli/dist/index.js showcase status --repo /tmp/uc-tiers-live-9YfGbp/t3-same_channel --run run.t3_same_channel_start --keyring /tmp/uc-tiers-live-9YfGbp/t3-same_channel/keyring.json`
Exit: 0
Stdout:
```text
showcase run.t3_same_channel_start: completed · passed
approval: approved
approved by user · tier same_channel_operator_confirmation

Add --json for the full machine-readable result envelope.
```

Result: PASS

## T3-os_presence. Assurance method os_presence records tier trusted_host_user_presence

Expected: A key capped at trusted_host_user_presence signs a os_presence approval; token/status tier is trusted_host_user_presence.

Actual:

Finished-run preparation commands:
- `node packages/cli/dist/index.js showcase start --repo /tmp/uc-tiers-live-9YfGbp/t3-os_presence --adhoc --select showcase.live.golden --json --idempotency-key t3-os_presence-start` -> exit 0
- `node packages/cli/dist/index.js showcase record-observation --repo /tmp/uc-tiers-live-9YfGbp/t3-os_presence --run run.t3_os_presence_start --item item.showcase.live.golden --text 'The live behaviour matched the expected outcome.' --json --idempotency-key t3-os_presence-observe` -> exit 0
- `node packages/cli/dist/index.js showcase record-verdict --repo /tmp/uc-tiers-live-9YfGbp/t3-os_presence --run run.t3_os_presence_start --item item.showcase.live.golden --verdict pass --actor agent --json --idempotency-key t3-os_presence-verdict` -> exit 0
- `node packages/cli/dist/index.js showcase finish --repo /tmp/uc-tiers-live-9YfGbp/t3-os_presence --run run.t3_os_presence_start --json --idempotency-key t3-os_presence-finish` -> exit 0

Command: `node packages/cli/dist/index.js showcase status --repo /tmp/uc-tiers-live-9YfGbp/t3-os_presence --run run.t3_os_presence_start`
Exit: 0
Stdout:
```text
showcase run.t3_os_presence_start: completed · passed
approval: pending

Add --json for the full machine-readable result envelope.
```

Command: `node packages/cli/dist/index.js showcase request-approval --repo /tmp/uc-tiers-live-9YfGbp/t3-os_presence --run run.t3_os_presence_start --json`
Exit: 0
Stdout:
```text
{"approval_request_schema":"ucase-approval-request-v1","binding":{"run_id":"run.t3_os_presence_start","finish_event_id":"evt.run.t3_os_presence_start.4","plan_content_hash":"sha256:0dab557731519d4aa11efd2408f9b22d98a548156afcba594b9cf6a37d573ec0","ledger_head_hash":"sha256:016f0055a00ba037b191cf53c04f2be5b220df859031dc2e4112e951900c07c0","evidence_digest":"sha256:23c02a2797a5db8c8208f13e39bea1b1139c94b011e06c74609375f455f54780","git_commit":"unknown","ci_freshness_digest":"sha256:983c6a70026ad4d8332ba68def013d05bdde99befa6cdd8f7a58c19017389afb"},"jti":"approval.d2f67ac9-a0dc-487e-be05-3aff9c224f82","iat":"2026-07-05T11:28:30.342Z","exp":"2026-07-05T11:43:30.342Z"}
```

Command: `node packages/cli/dist/index.js approve-run --request /tmp/uc-tiers-live-9YfGbp/t3-os_presence-request.json --key-file /tmp/uc-tiers-live-9YfGbp/keys-human/ci-signing-key.pem --key-id human-key-1 --out /tmp/uc-tiers-live-9YfGbp/t3-os_presence-token.json --assurance-method os_presence`
Exit: 0
Stdout:
```text
✓ showcase.approve_run
  approval_token_path: /tmp/uc-tiers-live-9YfGbp/t3-os_presence-token.json
  jti: approval.d2f67ac9-a0dc-487e-be05-3aff9c224f82
  decision: approved
  key_id: human-key-1
  assurance_method: os_presence
  assurance_tier: trusted_host_user_presence

Add --json for the full machine-readable result envelope.
```

Command: `node packages/cli/dist/index.js showcase approve --repo /tmp/uc-tiers-live-9YfGbp/t3-os_presence --run run.t3_os_presence_start --statement 'Method os_presence approval.' --approval-token /tmp/uc-tiers-live-9YfGbp/t3-os_presence-token.json --keyring /tmp/uc-tiers-live-9YfGbp/t3-os_presence/keyring.json --json`
Exit: 0
Stdout summary from JSON envelope:
```text
ok=true
complete=true
run_id=run.t3_os_presence_start
approval_state=approved
run_outcome=passed
approval_actor=user
approval_tier=trusted_host_user_presence
diagnostics=warning:showcase.approval_trust_anchor_caller_supplied: Approval-token verification is using caller-supplied trust material because use-cases.yml has no approval_trust pin.
```

Command: `node packages/cli/dist/index.js showcase status --repo /tmp/uc-tiers-live-9YfGbp/t3-os_presence --run run.t3_os_presence_start --keyring /tmp/uc-tiers-live-9YfGbp/t3-os_presence/keyring.json`
Exit: 0
Stdout:
```text
showcase run.t3_os_presence_start: completed · passed
approval: approved
approved by user · tier trusted_host_user_presence

Add --json for the full machine-readable result envelope.
```

Result: PASS

## T4. WebAuthn assertion records webauthn_hardware tier

Expected: Pinned WebAuthn credential verifies a crafted UP+UV assertion, approve-run emits webauthn_hardware, showcase approve records approved hardware tier.

Actual:

Finished-run preparation commands:
- `node packages/cli/dist/index.js showcase start --repo /tmp/uc-tiers-live-9YfGbp/t4-webauthn --adhoc --select showcase.live.golden --json --idempotency-key t4-start` -> exit 0
- `node packages/cli/dist/index.js showcase record-observation --repo /tmp/uc-tiers-live-9YfGbp/t4-webauthn --run run.t4_start --item item.showcase.live.golden --text 'The live behaviour matched the expected outcome.' --json --idempotency-key t4-observe` -> exit 0
- `node packages/cli/dist/index.js showcase record-verdict --repo /tmp/uc-tiers-live-9YfGbp/t4-webauthn --run run.t4_start --item item.showcase.live.golden --verdict pass --actor agent --json --idempotency-key t4-verdict` -> exit 0
- `node packages/cli/dist/index.js showcase finish --repo /tmp/uc-tiers-live-9YfGbp/t4-webauthn --run run.t4_start --json --idempotency-key t4-finish` -> exit 0

Command: `node packages/cli/dist/index.js showcase status --repo /tmp/uc-tiers-live-9YfGbp/t4-webauthn --run run.t4_start`
Exit: 0
Stdout:
```text
showcase run.t4_start: completed · passed
approval: pending

Add --json for the full machine-readable result envelope.
```

Command: `node packages/cli/dist/index.js showcase request-approval --repo /tmp/uc-tiers-live-9YfGbp/t4-webauthn --run run.t4_start --json`
Exit: 0
Stdout:
```text
{"approval_request_schema":"ucase-approval-request-v1","binding":{"run_id":"run.t4_start","finish_event_id":"evt.run.t4_start.4","plan_content_hash":"sha256:0dab557731519d4aa11efd2408f9b22d98a548156afcba594b9cf6a37d573ec0","ledger_head_hash":"sha256:fdafcba9e3787189bfddc4d6a63f6bc5b2c068a3bc0a83cc1b897c23ea1c91e2","evidence_digest":"sha256:6d0481c087d831215d07b208b0d47942fca02d4e8d65dbf50aa26e2800cbc80b","git_commit":"unknown","ci_freshness_digest":"sha256:5dea32ed17c5ace7ac549314f3555db52d753fac51fd35047ca7311107ed5774"},"jti":"approval.0159a65d-fb23-473a-8535-27b3d6f37139","iat":"2026-07-05T11:28:33.268Z","exp":"2026-07-05T11:43:33.268Z"}
```

Command: `node /tmp/uc-tiers-happy-rerun.mjs make-webauthn-assertion /tmp/uc-tiers-live-9YfGbp/t4-request.json /tmp/uc-tiers-live-9YfGbp/t4-webauthn-assertion.json`
Exit: 0
Stdout:
```text
assertion_path=/tmp/uc-tiers-live-9YfGbp/t4-webauthn-assertion.json
credential_id=t4-credential
challenge=70RAULWHQj4AzdmGp4MGzupMk_mNFZXC5lK3OtdQ2UU
```

Command: `node packages/cli/dist/index.js approve-run --request /tmp/uc-tiers-live-9YfGbp/t4-request.json --webauthn-assertion /tmp/uc-tiers-live-9YfGbp/t4-webauthn-assertion.json --out /tmp/uc-tiers-live-9YfGbp/t4-token.json`
Exit: 0
Stdout:
```text
✓ showcase.approve_run
  approval_token_path: /tmp/uc-tiers-live-9YfGbp/t4-token.json
  jti: approval.0159a65d-fb23-473a-8535-27b3d6f37139
  decision: approved
  credential_id: t4-credential
  assurance_method: webauthn
  assurance_tier: webauthn_hardware

Add --json for the full machine-readable result envelope.
```

Command: `node packages/cli/dist/index.js showcase approve --repo /tmp/uc-tiers-live-9YfGbp/t4-webauthn --run run.t4_start --statement 'Pinned WebAuthn assertion verified this sign-off.' --approval-token /tmp/uc-tiers-live-9YfGbp/t4-token.json --json`
Exit: 0
Stdout summary from JSON envelope:
```text
ok=true
complete=true
run_id=run.t4_start
approval_state=approved
run_outcome=passed
approval_actor=user
approval_tier=webauthn_hardware
diagnostics=(none)
```

Command: `node packages/cli/dist/index.js showcase status --repo /tmp/uc-tiers-live-9YfGbp/t4-webauthn --run run.t4_start`
Exit: 0
Stdout:
```text
showcase run.t4_start: completed · passed
approval: approved
approved by user · tier webauthn_hardware

Add --json for the full machine-readable result envelope.
```

Result: PASS

## T5. Signed rejection records verified actor and tier

Expected: approve-run signs decision rejected; showcase reject records a trusted rejection; status reports approval_state rejected with actor user and trusted_host_user_presence. The reject command exits 1 by design because the run is rejected.

Actual:

Finished-run preparation commands:
- `node packages/cli/dist/index.js showcase start --repo /tmp/uc-tiers-live-9YfGbp/t5-reject --adhoc --select showcase.live.golden --json --idempotency-key t5-start` -> exit 0
- `node packages/cli/dist/index.js showcase record-observation --repo /tmp/uc-tiers-live-9YfGbp/t5-reject --run run.t5_start --item item.showcase.live.golden --text 'The live behaviour matched the expected outcome.' --json --idempotency-key t5-observe` -> exit 0
- `node packages/cli/dist/index.js showcase record-verdict --repo /tmp/uc-tiers-live-9YfGbp/t5-reject --run run.t5_start --item item.showcase.live.golden --verdict pass --actor agent --json --idempotency-key t5-verdict` -> exit 0
- `node packages/cli/dist/index.js showcase finish --repo /tmp/uc-tiers-live-9YfGbp/t5-reject --run run.t5_start --json --idempotency-key t5-finish` -> exit 0

Command: `node packages/cli/dist/index.js showcase status --repo /tmp/uc-tiers-live-9YfGbp/t5-reject --run run.t5_start`
Exit: 0
Stdout:
```text
showcase run.t5_start: completed · passed
approval: pending

Add --json for the full machine-readable result envelope.
```

Command: `node packages/cli/dist/index.js showcase request-approval --repo /tmp/uc-tiers-live-9YfGbp/t5-reject --run run.t5_start --json`
Exit: 0
Stdout:
```text
{"approval_request_schema":"ucase-approval-request-v1","binding":{"run_id":"run.t5_start","finish_event_id":"evt.run.t5_start.4","plan_content_hash":"sha256:0dab557731519d4aa11efd2408f9b22d98a548156afcba594b9cf6a37d573ec0","ledger_head_hash":"sha256:a9de11e18daf526b6f1415a0dad5fc87dec7037214a0c3c0f194136971fd6418","evidence_digest":"sha256:6820bcd8fdf202941e76f8497533ffb4a1ce9e27041ab393bc2e6fc61ac962e7","git_commit":"unknown","ci_freshness_digest":"sha256:2262e7e47d0cd9d55b9a8fde5078e06e24326a6c26b8abcc00c3f7e0b7e36936"},"jti":"approval.3c44e974-79d0-4036-b4b0-789d09f7ad70","iat":"2026-07-05T11:28:35.881Z","exp":"2026-07-05T11:43:35.881Z"}
```

Command: `node packages/cli/dist/index.js approve-run --request /tmp/uc-tiers-live-9YfGbp/t5-request.json --key-file /tmp/uc-tiers-live-9YfGbp/keys-human/ci-signing-key.pem --key-id human-key-1 --out /tmp/uc-tiers-live-9YfGbp/t5-token.json --decision rejected`
Exit: 0
Stdout:
```text
✓ showcase.approve_run
  approval_token_path: /tmp/uc-tiers-live-9YfGbp/t5-token.json
  jti: approval.3c44e974-79d0-4036-b4b0-789d09f7ad70
  decision: rejected
  key_id: human-key-1
  assurance_method: os_presence
  assurance_tier: trusted_host_user_presence

Add --json for the full machine-readable result envelope.
```

Command: `node packages/cli/dist/index.js showcase reject --repo /tmp/uc-tiers-live-9YfGbp/t5-reject --run run.t5_start --statement 'Genuine human rejection.' --approval-token /tmp/uc-tiers-live-9YfGbp/t5-token.json --keyring /tmp/uc-tiers-live-9YfGbp/t5-reject/keyring.json --json`
Exit: 1
Stdout summary from JSON envelope:
```text
ok=true
complete=true
run_id=run.t5_start
approval_state=rejected
run_outcome=passed
approval_actor=user
approval_tier=trusted_host_user_presence
diagnostics=warning:showcase.approval_trust_anchor_caller_supplied: Approval-token verification is using caller-supplied trust material because use-cases.yml has no approval_trust pin.
```

Command: `node packages/cli/dist/index.js showcase status --repo /tmp/uc-tiers-live-9YfGbp/t5-reject --run run.t5_start --keyring /tmp/uc-tiers-live-9YfGbp/t5-reject/keyring.json --json`
Exit: 0
Stdout:
```text
{"schema_version":1,"protocol_version":1,"command":"showcase.status","ok":true,"complete":true,"data":{"schema_version":1,"run_id":"run.t5_start","complete":true,"execution_status":"completed","run_outcome":"passed","approval_state":"rejected","unresolved_failure_count":0,"approval":{"actor_type":"user","assurance_tier":"trusted_host_user_presence"},"items":[{"plan_item_id":"item.showcase.live.golden","verdict":"pass","item_currency":"current","verification_state":"requirements_met","latest_observation_event_id":"evt.run.t5_start.2","latest_verdict_event_id":"evt.run.t5_start.3"}],"known_gaps":[],"diagnostic_summary":{}},"diagnostics":[{"code":"showcase.approval_trust_anchor_caller_supplied","severity":"warning","message":"Approval-token verification is using caller-supplied trust material because use-cases.yml has no approval_trust pin.","source_path":null,"json_pointer":null,"entity_id":null,"related_ids":[]}],"context":{"workspace_root":"/private/tmp/uc-tiers-live-9YfGbp/t5-reject","data_root":"/private/tmp/uc-tiers-live-9YfGbp/t5-reject","component_id":"presentation-skills","workspace_snapshot":{"repository_id":"unknown","vcs":"unknown","head_revision":"unknown","dirty":false,"working_tree_digest":"sha256:0000000000000000000000000000000000000000000000000000000000000000","component_id":"presentation-skills","captured_at":"1970-01-01T00:00:00.000Z"}}}
```

Result: PASS

## T6. Policy floor webauthn_hardware accepts hardware and rejects lower tier

Expected: A row with minimum_assurance_tier webauthn_hardware accepts a WebAuthn approval and rejects an os_presence/trusted_host_user_presence approval as assurance too low.

Actual:

Hardware acceptance:

Finished-run preparation commands:
- `node packages/cli/dist/index.js showcase start --repo /tmp/uc-tiers-live-9YfGbp/t6-hardware-accept --adhoc --select showcase.live.golden --json --idempotency-key t6-hw-start` -> exit 0
- `node packages/cli/dist/index.js showcase record-observation --repo /tmp/uc-tiers-live-9YfGbp/t6-hardware-accept --run run.t6_hw_start --item item.showcase.live.golden --text 'The live behaviour matched the expected outcome.' --json --idempotency-key t6-hw-observe` -> exit 0
- `node packages/cli/dist/index.js showcase record-verdict --repo /tmp/uc-tiers-live-9YfGbp/t6-hardware-accept --run run.t6_hw_start --item item.showcase.live.golden --verdict pass --actor agent --json --idempotency-key t6-hw-verdict` -> exit 0
- `node packages/cli/dist/index.js showcase finish --repo /tmp/uc-tiers-live-9YfGbp/t6-hardware-accept --run run.t6_hw_start --json --idempotency-key t6-hw-finish` -> exit 0

Command: `node packages/cli/dist/index.js showcase status --repo /tmp/uc-tiers-live-9YfGbp/t6-hardware-accept --run run.t6_hw_start`
Exit: 0
Stdout:
```text
showcase run.t6_hw_start: completed · passed
approval: pending

Add --json for the full machine-readable result envelope.
```

Command: `node packages/cli/dist/index.js showcase request-approval --repo /tmp/uc-tiers-live-9YfGbp/t6-hardware-accept --run run.t6_hw_start --json`
Exit: 0
Stdout:
```text
{"approval_request_schema":"ucase-approval-request-v1","binding":{"run_id":"run.t6_hw_start","finish_event_id":"evt.run.t6_hw_start.4","plan_content_hash":"sha256:057b618d1eb4e61c772c7558ef3b6d758f0b5aa3ccfc12f7d327b8148900e545","ledger_head_hash":"sha256:88d2b550933e50ce0f5de5dee01105e180325a2529dab7a08877a222a168b82c","evidence_digest":"sha256:a15929667a0c68b47c6dba2789ecf654402ce5393b3af2300267540311ae91da","git_commit":"unknown","ci_freshness_digest":"sha256:7ce8dc7c31537f78bb86b7b3e08ee31b1f3f81507a9520037062f4aa7e0089eb"},"jti":"approval.8bb40869-1476-4b54-812d-29906208eeab","iat":"2026-07-05T11:28:38.128Z","exp":"2026-07-05T11:43:38.128Z"}
```

Command: `node /tmp/uc-tiers-happy-rerun.mjs make-webauthn-assertion /tmp/uc-tiers-live-9YfGbp/t6-hw-request.json /tmp/uc-tiers-live-9YfGbp/t6-webauthn-assertion.json`
Exit: 0
Stdout:
```text
assertion_path=/tmp/uc-tiers-live-9YfGbp/t6-webauthn-assertion.json
credential_id=t6-credential
challenge=5jFGo1e-JxedVEq24iaYijDSAOJB7jqVEwt1nqr-C98
```

Command: `node packages/cli/dist/index.js approve-run --request /tmp/uc-tiers-live-9YfGbp/t6-hw-request.json --webauthn-assertion /tmp/uc-tiers-live-9YfGbp/t6-webauthn-assertion.json --out /tmp/uc-tiers-live-9YfGbp/t6-hw-token.json`
Exit: 0
Stdout:
```text
✓ showcase.approve_run
  approval_token_path: /tmp/uc-tiers-live-9YfGbp/t6-hw-token.json
  jti: approval.8bb40869-1476-4b54-812d-29906208eeab
  decision: approved
  credential_id: t6-credential
  assurance_method: webauthn
  assurance_tier: webauthn_hardware

Add --json for the full machine-readable result envelope.
```

Command: `node packages/cli/dist/index.js showcase approve --repo /tmp/uc-tiers-live-9YfGbp/t6-hardware-accept --run run.t6_hw_start --statement 'Hardware-tier policy approval.' --approval-token /tmp/uc-tiers-live-9YfGbp/t6-hw-token.json --json`
Exit: 0
Stdout summary from JSON envelope:
```text
ok=true
complete=true
run_id=run.t6_hw_start
approval_state=approved
run_outcome=passed
approval_actor=user
approval_tier=webauthn_hardware
diagnostics=(none)
```

Command: `node packages/cli/dist/index.js showcase status --repo /tmp/uc-tiers-live-9YfGbp/t6-hardware-accept --run run.t6_hw_start`
Exit: 0
Stdout:
```text
showcase run.t6_hw_start: completed · passed
approval: approved
approved by user · tier webauthn_hardware

Add --json for the full machine-readable result envelope.
```

Lower-tier rejection:

Finished-run preparation commands:
- `node packages/cli/dist/index.js showcase start --repo /tmp/uc-tiers-live-9YfGbp/t6-lower-reject --adhoc --select showcase.live.golden --json --idempotency-key t6-low-start` -> exit 0
- `node packages/cli/dist/index.js showcase record-observation --repo /tmp/uc-tiers-live-9YfGbp/t6-lower-reject --run run.t6_low_start --item item.showcase.live.golden --text 'The live behaviour matched the expected outcome.' --json --idempotency-key t6-low-observe` -> exit 0
- `node packages/cli/dist/index.js showcase record-verdict --repo /tmp/uc-tiers-live-9YfGbp/t6-lower-reject --run run.t6_low_start --item item.showcase.live.golden --verdict pass --actor agent --json --idempotency-key t6-low-verdict` -> exit 0
- `node packages/cli/dist/index.js showcase finish --repo /tmp/uc-tiers-live-9YfGbp/t6-lower-reject --run run.t6_low_start --json --idempotency-key t6-low-finish` -> exit 0

Command: `node packages/cli/dist/index.js showcase status --repo /tmp/uc-tiers-live-9YfGbp/t6-lower-reject --run run.t6_low_start`
Exit: 0
Stdout:
```text
showcase run.t6_low_start: completed · passed
approval: pending

Add --json for the full machine-readable result envelope.
```

Command: `node packages/cli/dist/index.js showcase request-approval --repo /tmp/uc-tiers-live-9YfGbp/t6-lower-reject --run run.t6_low_start --json`
Exit: 0
Stdout:
```text
{"approval_request_schema":"ucase-approval-request-v1","binding":{"run_id":"run.t6_low_start","finish_event_id":"evt.run.t6_low_start.4","plan_content_hash":"sha256:057b618d1eb4e61c772c7558ef3b6d758f0b5aa3ccfc12f7d327b8148900e545","ledger_head_hash":"sha256:e1578f6a537bface77f59bfc7158d340f6127ebb1da5aaf9d31baa3fa7befa0f","evidence_digest":"sha256:2a0a972940daa5b7b64836268f917e3998272f54e60e0bd138de0b17a9c2d0fb","git_commit":"unknown","ci_freshness_digest":"sha256:485265ca6891ab1d629552ebf461c81b9a3a39312183e1ca5e6169c8d8890bb1"},"jti":"approval.8ac6bd79-c751-4845-8eaf-786fc7f4ffa5","iat":"2026-07-05T11:28:40.623Z","exp":"2026-07-05T11:43:40.623Z"}
```

Command: `node packages/cli/dist/index.js approve-run --request /tmp/uc-tiers-live-9YfGbp/t6-low-request.json --key-file /tmp/uc-tiers-live-9YfGbp/keys-human/ci-signing-key.pem --key-id human-key-1 --out /tmp/uc-tiers-live-9YfGbp/t6-low-token.json --assurance-method os_presence`
Exit: 0
Stdout:
```text
✓ showcase.approve_run
  approval_token_path: /tmp/uc-tiers-live-9YfGbp/t6-low-token.json
  jti: approval.8ac6bd79-c751-4845-8eaf-786fc7f4ffa5
  decision: approved
  key_id: human-key-1
  assurance_method: os_presence
  assurance_tier: trusted_host_user_presence

Add --json for the full machine-readable result envelope.
```

Command: `node packages/cli/dist/index.js showcase approve --repo /tmp/uc-tiers-live-9YfGbp/t6-lower-reject --run run.t6_low_start --statement 'Lower-tier token should not meet hardware floor.' --approval-token /tmp/uc-tiers-live-9YfGbp/t6-low-token.json --json`
Exit: 1
Stdout summary from JSON envelope:
```text
ok=false
complete=false
run_id=undefined
approval_state=undefined
run_outcome=undefined
approval_actor=(none)
approval_tier=(none)
diagnostics=error:showcase.approval_assurance_too_low: User approval token rejected: ASSURANCE_TOO_LOW (approval token assurance tier trusted_host_user_presence does not meet floor webauthn_hardware)
```

Command: `node packages/cli/dist/index.js showcase status --repo /tmp/uc-tiers-live-9YfGbp/t6-lower-reject --run run.t6_low_start`
Exit: 0
Stdout:
```text
showcase run.t6_low_start: completed · passed
approval: pending

Add --json for the full machine-readable result envelope.
```

Result: PASS

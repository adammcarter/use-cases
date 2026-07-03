# TEST-MATRIX — use-case-matrix v0.0.3

Repo-owned acceptance source of truth. Says what must be true in real use, how it
was proven, the observed evidence, and any open red signals.

| Field | Value |
|---|---|
| Release | **use-case-matrix@0.0.3** |
| Branch / commit | `main` @ `14d9b22` |
| Run date | 2026-07-03 |
| Artifact under test | `use-case-matrix-0.0.3.tgz` (433,738 bytes) packed via `pnpm pack`, installed into a clean throwaway project (`/tmp/ucm-accept-rig`, 75 deps) — **not** the dev checkout |
| Bins exposed | `uc`, `use-case-matrix`, `uc-mcp`, `use-case-matrix-mcp` |
| Automated gate | `pnpm test` → **677 passed / 85 files / 0 fail** |
| Overall | ✅ **PASS** — 0 product defects; all rows green (signed-mint of proofs is CI-scoped, see Notes) |

Acceptance discipline: unit tests *support* a row but do not replace live usage
proof. Every row below was run for real against the installed tarball unless the
row is explicitly marked as covered by the automated suite.

---

## A · Package install & entrypoints

| ID | Scenario | Command | Expected | Result |
|---|---|---|---|---|
| A1 | Tarball installs clean | `npm i use-case-matrix-0.0.3.tgz` in empty project | installs, no errors | ✅ `added 75 packages in 2s` |
| A2 | Both bins resolve | `ls node_modules/.bin` | `uc`, `uc-mcp`, `use-case-matrix`, `use-case-matrix-mcp` present + executable | ✅ all four present, `uc-mcp` executable |
| A3 | CLI version | `uc version` | prints `0.0.3` | ✅ `0.0.3` |
| A4 | MCP stdio handshake | `initialize` + `tools/list` over stdio | initializes, lists tools | ✅ handshake OK, **20 tools** listed |

## B · CLI core lifecycle (host-agnostic)

| ID | Scenario | Command | Expected | Result |
|---|---|---|---|---|
| B1 | Scaffold workspace | `uc init --repo WS` | creates `use-cases.yml` + `use-cases/` with 1 example row | ✅ exit 0; workspace + example row created |
| B2 | Validate matrix | `uc matrix validate` | `ok:true`, `valid:true` | ✅ ok:true, valid:true |
| B3 | List use cases | `uc matrix list` | `ok:true`, 1 row | ✅ ok:true, returned:1 |
| B4 | Compose status | `uc matrix status` | `ok:true` | ✅ ok:true |
| B5 | Upsert row | `uc matrix upsert --use-case-json <complete row>` | schema-validated add; rows 1→2 | ✅ ok:true (correctly rejects incomplete rows with schema diagnostics) |
| B6 | Soft-remove row | `uc matrix remove --use-case … --reason …` | `ok:true` (tombstone) | ✅ ok:true |
| B7 | Schema list / validate-fixtures | `uc schema list` / `… validate-fixtures` | `ok:true` | ✅ both ok:true |
| B8 | Doctor roots | `uc doctor roots` | `ok:true` | ✅ ok:true |
| B9 | Workflow mode | `uc workflow mode` | `ok:true` | ✅ ok:true |
| B10 | Evidence record + status | `uc evidence record …` / `uc evidence status` | `ok:true`, ledger updated | ✅ both ok:true |
| B11 | Plans | `uc plan showcase` / `uc plan walkthrough` | `ok:true` | ✅ both ok:true |
| B12 | Capsules | `uc capsule list` / `uc capsule validate` | `ok:true` | ✅ both ok:true (plan/run need a demo capsule; scaffold ships none — covered by capsule unit tests) |
| B13 | Migrate legacy matrix | `uc migrate test-matrix --source LEGACY.md --dry-run` | `ok:true`, previews migration | ✅ ok:true |

## C · Trust / markers surface (CLI-only)

| ID | Scenario | Command | Expected | Result |
|---|---|---|---|---|
| C1 | Bind row to code | `uc bind --row … --file src/feature.ts --mode explicit --start-line 1 --end-line 3` | inserts `//: @use-case:` markers | ✅ ok:true, markers inserted around the span |
| C2 | Scan freshness | `uc scan` | `ok:true` | ✅ ok:true |
| C3 | Verify runs real verifier | `uc verify --all --out results.json` | runs the row's verifier, writes unsigned results | ✅ ran verifier; correctly reports `status:fail` for the scaffold's placeholder verifier (see N1) |
| C4 | Prove refuses failing row | `uc prove --all --verification-results results.json --trusted-ci …` | **refuses** to mint from a failed verification | ✅ ok:false, `reason: RESULT_FAILED`, `proof_event_appended:false` — safety invariant holds |
| C5 | Validate ledger (with key) | `uc validate-ledger --public-key trusted-ci-public-key.pem` | `ok:true`, signatures verified | ✅ ok:true, `evidence_valid:true`, 11/11 verified (see N2 for the no-key path) |

## D · Showcase lifecycle

| ID | Scenario | Command | Expected | Result |
|---|---|---|---|---|
| D1 | Start run | `uc showcase start --adhoc --select <uc>` | `ok:true`, run id issued | ✅ ok:true, `run.acc_start` |
| D2 | Record observation | `uc showcase record-observation …` | `ok:true` | ✅ ok:true |
| D3 | Record verdict | `uc showcase record-verdict --verdict pass` | `ok:true` | ✅ ok:true |
| D4 | Finish run | `uc showcase finish` | `ok:true` | ✅ ok:true |
| D5 | Status replay | `uc showcase status` | `ok:true` | ✅ ok:true |

## E · MCP surface (installed `uc-mcp` bin)

| ID | Scenario | Command | Expected | Result |
|---|---|---|---|---|
| E1 | Tool inventory | `tools/list` | 20 conservative v1 tools; no signing/binding tools | ✅ 20 tools; trust surface absent |
| E2 | Read tools | `matrix_validate/list/status`, `evidence_status`, `doctor_roots`, `plan_showcase/walkthrough`, `host_doctor`, `showcase_status`, `showcase_request_approval` | `ok:true` | ✅ all ok:true |
| E3 | Write-mode gating | any write tool without `UCM_MCP_WRITE` | `ok:false`, `mcp.write_mode_required` | ✅ all 10 write tools gate (evidence_record/void, use_case_upsert/remove, capsule_run, showcase_start/record-observation/record-verdict/decide/finish) |
| E4 | Write with mode | `evidence_record` with `UCM_MCP_WRITE=1` + `allow_write` | `ok:true`, ledger updated | ✅ ok:true |
| E5 | CLI/MCP envelope parity — missing repo | `matrix_validate/list/status` on non-existent repo, both transports | byte-identical `ok:false` / `workspace.not_found`; CLI exit 2 | ✅ parity holds (regression test `p9-mcp` asserts `toEqual`) |

## F · Host integration × 4 hosts

| ID | Scenario | Command | Expected | claude | codex | copilot | opencode |
|---|---|---|---|---|---|---|---|
| F1 | Host doctor | `uc host doctor --host H` | `ok:true` | ✅ | ✅ | ✅ | ✅ |
| F2 | Host conformance | `uc host conformance --host H` | `ok:true` | ✅ | ✅ | ✅ | ✅ |
| F3 | Project (dry-run) | `uc host project --host H --dry-run` | `ok:true`, lists operations | ✅ (2 ops) | ✅ | ✅ | ✅ |
| F4 | Project write→revert | `… --write` then `… --revert` (claude) | writes `.claude/use-case-matrix.md`, revert removes it | ✅ write+revert clean | — | — | — |

## G · Self-dogfood (product validates its own repo)

| ID | Scenario | Command | Expected | Result |
|---|---|---|---|---|
| G1 | Validate own matrix | `uc matrix validate --repo <this repo>` | `ok:true`, 0 broken refs, 0 ambiguous | ✅ ok:true, **83 use cases**, broken_refs:0, ambiguous:0 |
| G2 | Compose own status | `uc matrix status --repo <this repo>` | `ok:true` | ✅ ok:true |
| G3 | Validate own ledger | `uc validate-ledger --public-key .use-cases/trusted-ci-public-key.pem` | `ok:true`, signatures verified | ✅ ok:true, evidence_valid:true, 11/11 verified |
| G4 | Scan own markers | `uc scan --public-key … --policy-mode release` | `ok:true` | ✅ ok:true (feature + release modes) |

---

## Notes & observations (non-blocking)

- **N1 — Scaffold verifier fails by design.** `uc init` ships a placeholder
  verifier `["false", "TODO-replace-…"]` that always exits non-zero, so a fresh
  workspace can never mint a passing proof. `verify` reporting `fail` and `prove`
  refusing to mint (rows C3/C4) is the *intended* safety behavior, not a defect.
- **N2 — `validate-ledger`/`scan` without `--public-key`.** On a repo whose proofs
  are signed, running these without a trusted key yields a hard
  `UNKNOWN_KEY_ID` error (exit 4) rather than a clearly-labelled "no key → proofs
  UNPROVEN" soft state. CI always passes the committed
  `.use-cases/trusted-ci-public-key.pem`, and both commands pass with it (G3/G4).
  **Follow-up candidate (not a v0.0.3 blocker):** auto-discover a workspace-declared
  public key, and/or soften the no-key path to an explicit UNPROVEN downgrade.
- **N3 — Signed proof minting is CI-scoped.** The full `verify → prove(sign) →
  validate-ledger(verify signature)` happy path requires the CI signing key and is
  covered by the automated `tests/release/p14-release-gate` + marker suites; the
  live matrix proves the *guard* behavior (C4) and the *verification* side (G3).

# v1 Public Surface Inventory

Factual inventory of the current public surface, produced by a read-only audit
(Phase 1). This is the working reference for the v1 contract declaration
(`docs/reference/stability.md`) and the remaining Phase 1 gap-fill work. Update
it as the surface changes.

## CLI — 44 commands

Groups: `version`, `init`, `schema {list,validate-fixtures}`, `matrix
{validate,list,status,upsert,remove}`, `plan {showcase,walkthrough,cards}`,
`capsule {validate,list,plan,run}`, `evidence {record,status,void}`, `showcase
{start,record-observation,record-verdict,decide,pause,resume,finish,…}`, `host
{…}`, `doctor {skills,package,roots}`, and the trust engine `bind`, `scan`,
`verify`, `prove`, `validate-ledger`.

- **Global flags:** `--json`, `--version`/`-v`, `--repo`, `--data-root`, `--component`.
- **Envelope:** `{schema_version, protocol_version, command, ok, complete, data, diagnostics, context}` — declared stable.
- **Exit codes:** `0` ok · `1` failed/validation · `2` bad args · `3` integrity blocked · `4` unsafe path escape.
- **Gap — `--json` consistency:** `bind`, `scan`, `prove`, `verify`, `validate-ledger` emit JSON unconditionally rather than via a uniform `--json` toggle. Normalise for v1.

## MCP — 20 tools, 0 resources, 0 prompts

- **Mutating tools (10):** `use_case_upsert`, `use_case_remove`, `evidence_record`, `evidence_void`, `capsule_run`, `showcase_start`, `showcase_record_observation`, `showcase_record_verdict`, `showcase_decide`, `showcase_finish`.
- **Safety posture (already strong):**
  - Input validation: comprehensive (typed arg parsing, required-field checks, path-traversal protection, timeout guards).
  - `prove` / signing: **not exposed** over MCP (evidence model only; approval is CLI-mediated). ✅
  - Generic shell: **none**. `capsule_run` is bounded argv behind a triple gate (env flag + `execute_commands` + capsule permission), with redacted stdout/stderr. ✅
  - Workspace roots: locked (explicit `repo` param; `data_root` escape rejected). ✅
- **Gaps:** no resources, no prompts; no output rate-limiting or size caps.

## Schemas — 26 present, 5 gaps

Present (under `schemas/v1/`): cli-result, common, demo-capsule, evidence-append-result, evidence-event, evidence-status-result, host-profile, host-status-result, matrix-{list,mutation,validation}-result, migration-test-matrix-result, presentation-plan(+result), showcase-{approval,event,event-append,finish,run-status,start}-result, showcase-event, use-case-file, workflow-mode, workspace-config. Plus the markers schemas (`proof-event`, registry, …) under `packages/ucm-core/src/markers/schemas/`.

**Gaps to close:**
1. `marker` — `ucase-marker-v1` id exists in constants but no schema file.
2. `release-gate` — gating logic + `required_for_release` exist but no result schema.
3. `ledger` — the proof/evidence JSONL is validated per-line via `proof-event`; no whole-ledger schema (ordering/chain).
4. `keyring` — public-key registry/verification exists but no schema for key management.
5. `mcp-tool-results` — MCP returns the CLI envelope; no dedicated documented schema.

**Gap — validation coverage:** no test asserts that *every* CLI/MCP JSON output validates against its schema. Add a conformance test.

## Error codes — not centralized

- ~108 diagnostic call sites; **no single registry**.
- 5 enum families (`MarkerErrorCode`, `RegistryErrorCode`, `EvidenceErrorCode`, `SwiftFuncErrorCode`, `SignatureFailureCode`) + ~21 `PresentationSkillsError` string literals.
- **Plan:** introduce a central `@use-cases-plugin/core/errors` registry of stable `UCP_*` codes (e.g. `UCP_MARKER_MALFORMED`, `UCP_EVIDENCE_ROW_MISSING`), map the ~57 existing codes, keep the enums as type-safe wrappers during migration (additive, non-breaking).

## Phase 1 remaining workstreams (after this contract declaration)

- [ ] Close the 5 schema gaps + register their `$id`s.
- [ ] Conformance test: every CLI `--json` output validates against a schema.
- [ ] `--json` consistency across all commands.
- [x] `UCP_*` error-code registry (additive) + generated error-code docs page — `packages/ucm-core/src/errors/registry.ts` + `docs/reference/error-codes.md`.
- [ ] (Phase 4) MCP resources + prompts; rate-limit/size caps.

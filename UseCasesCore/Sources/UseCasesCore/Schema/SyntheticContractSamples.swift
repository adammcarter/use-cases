/// The representative documents the gap schemas are validated against.
///
/// These are the TypeScript's own samples, character for character; a schema
/// that drifts away from the shape the code produces fails against them first.
enum SyntheticContractSamples {
  static let evidenceEventSample = #"""
  {"schema_version":1,"event_type":"evidence_recorded","event_id":"evt_evidence_synthetic",\#
  "aggregate_id":"evidence.synthetic","sequence":1,"recorded_at":"2026-06-25T00:00:00.000Z",\#
  "actor_type":"agent","host_surface":"codex.cli","idempotency_key":"synthetic",\#
  "intent_digest":\#
  "sha256:1111111111111111111111111111111111111111111111111111111111111111","payload":\#
  {"evidence_kind":"manual_observation","use_case_ids":["synthetic.case"],"verifier":\#
  {"type":"agent"},"verdict":"pass","summary":"Synthetic evidence contract sample.",\#
  "targets":[{"use_case_id":"synthetic.case","use_case_semantic_hash":\#
  "sha256:2222222222222222222222222222222222222222222222222222222222222222"}],"kind":\#
  "manual_observation","captured_at":"2026-06-25T00:00:00.000Z","result":"pass","producer":\#
  {"type":"agent","identity":"synthetic"},"method":{"type":"reported"}}}
  """#

  static let presentationPlanSample = #"""
  {"schema_version":1,"plan_id":"plan.synthetic.showcase","plan_content_hash":\#
  "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",\#
  "generated_at":"2026-06-25T00:00:00.000Z","mode":"showcase","complete":true,\#
  "prepared_not_performed":true,"readiness":"ready_with_evidence_gaps",\#
  "integrity_acknowledgement_required":false,"selection_method":"deterministic",\#
  "selection_profile":{"id":"showcase-v1","version":1,"digest":\#
  "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"},\#
  "input_snapshot":{"matrix_digest":\#
  "sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",\#
  "evidence_basis_digest":\#
  "sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",\#
  "changed_paths":[],"freshness_policy":{"id":"default-v1","digest":\#
  "sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",\#
  "evaluated_at":"2026-06-25T00:00:00.000Z"},"host_surface":"codex.cli","workflow":\#
  {"effective_mode":"continuous","source":"default","advisory":true}},"workspace_snapshot":\#
  {"repository_id":"synthetic","vcs":"unknown","head_revision":"unknown","dirty":false,\#
  "working_tree_digest":\#
  "sha256:0000000000000000000000000000000000000000000000000000000000000000",\#
  "component_id":"\#(ProductVersion.defaultComponentIdentifier)","captured_at":\#
  "2026-06-25T00:00:00.000Z"},"environment_expectations":{"host_surfaces":["codex.cli"]},\#
  "audience":"reviewer","timebox_seconds":600,"sections":[],"selected_items":[],\#
  "exclusions":[],"known_gaps":[]}
  """#

  static let showcaseEventSample = #"""
  {"schema_version":1,"event_type":"observation_recorded","event_id":\#
  "evt_showcase_synthetic_1","run_id":"run.synthetic","aggregate_id":"run.synthetic",\#
  "sequence":2,"recorded_at":"2026-06-25T00:01:00.000Z","actor_type":"agent",\#
  "host_surface":"codex.cli","idempotency_key":"synthetic-showcase-observation",\#
  "intent_digest":\#
  "sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff","payload":\#
  {"plan_item_id":"item.synthetic.case","observation":"Synthetic observation."}}
  """#

  static let showcaseStatusSample = #"""
  {"schema_version":1,"run_id":"run.synthetic","complete":true,"execution_status":"running",\#
  "run_outcome":"incomplete","approval_state":"pending","unresolved_failure_count":0,\#
  "items":[{"plan_item_id":"item.synthetic.case","verdict":"none","item_currency":"unknown",\#
  "verification_state":"requirements_unmet","latest_observation_event_id":\#
  "evt_showcase_synthetic_1","latest_verdict_event_id":null}],"known_gaps":[],\#
  "diagnostic_summary":{}}
  """#

  static let newSchemaSamples: [(String, String)] = [
    (
      "marker.schema.json",
      #"""
      {"marker_schema_id":"ucase-marker-v1","kind":"start","slug":"checkout.apply_coupon",\#
      "row_id":"checkout.apply_coupon","suffix":null,"role":"row","file":\#
      "Sources/Checkout/CouponService.swift","line":3,"column":1}
      """#
    ),
    (
      "release-gate-result.schema.json",
      #"""
      {"schema_version":1,"policy_mode":"release","passed":false,"generated_at":\#
      "2026-06-25T00:00:00.000Z","summary":{"rows_total":1,"rows_required":1,\#
      "rows_blocked":1},"blocked_row_ids":["checkout.apply_coupon"],"rows":[{"row_id":\#
      "checkout.apply_coupon","status":"UNPROVEN","required_for_release":true,\#
      "policy_block":true,"reasons":["row has a registered binding but no trusted proof \#
      event"]}]}
      """#
    ),
    (
      "ledger.schema.json",
      #"""
      {"ledger_schema_id":"ucase-evidence-ledger-v1","append_only":true,"entries":[{"schema":\#
      "ucase-proof-event-v1","event_id":"evt_0001","created_at":"2026-06-25T00:00:00.000Z",\#
      "row":{"row_id":"checkout.apply_coupon"},"signature":{"alg":"ed25519","key_id":\#
      "ci-key-1","value":"c2lnbmF0dXJl"}}]}
      """#
    ),
    (
      "keyring.schema.json",
      #"""
      {"keyring_schema_id":"ucase-public-key-registry-v1","keys":[{"key_id":"ci-key-1",\#
      "algorithm":"ed25519","public_key":"-----BEGIN PUBLIC KEY-----\nMCowBQYDK2Vw\#
      AyEAexample=\n-----END PUBLIC KEY-----\n",\#
      "valid_from":"2026-01-01T00:00:00.000Z","valid_until":null,"status":"active"}]}
      """#
    ),
    (
      "authority.schema.json",
      #"""
      {"type":"ci","provider":"github-actions","repository":"use-cases/use-cases","ref":\#
      "refs/heads/main","commit":"0123456789abcdef0123456789abcdef01234567","run_id":\#
      "1234567890","actor":"octocat","protected_ref":null,"event":"push"}
      """#
    ),
    (
      "approval-token.schema.json",
      #"""
      {"approval_token_schema":"ucase-approval-token-v1","binding":{"run_id":"run.alpha",\#
      "finish_event_id":"evt.run.alpha.7","plan_content_hash":"sha256:plan",\#
      "ledger_head_hash":"sha256:head","evidence_digest":"sha256:evidence","git_commit":\#
      "0123456789abcdef0123456789abcdef01234567","ci_freshness_digest":"sha256:ci"},"jti":\#
      "approval.9d8f54b2-7a0d-4bc2-ad35-9035dcb623c5","iat":"2026-06-28T12:05:00.000Z",\#
      "exp":"2026-06-28T12:20:00.000Z","created_at":"2026-06-28T12:05:00.000Z","decision":\#
      "approved","signature":{"alg":"ed25519","key_id":"human-key-1","value":\#
      "c2lnbmF0dXJl"}}
      """#
    ),
  ]
}

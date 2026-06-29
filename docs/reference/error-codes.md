<!-- GENERATED FILE — do not edit by hand.
     Regenerate with `node packages/ucm-core/scripts/generate-error-codes.mjs`
     (source of truth: packages/ucm-core/src/errors/registry.ts). -->

# Error Codes

Stable `UCP_*` error codes are part of the [public API](./stability.md). Each
code below is a versioned contract: a code is only removed or repurposed in a
**major** release; new codes ship additively in a **minor**. Diagnostics carry
the code in their `code` field.

There are **66** codes across **9** surfaces.

## Marker grammar

| Code | Severity | Message |
|---|---|---|
| `UCP_MARKER_DUPLICATE_BINDING_SLUG` | error | Duplicate binding slug within the same source. |
| `UCP_MARKER_END_MALFORMED` | error | Marker end line is malformed. |
| `UCP_MARKER_END_MISMATCHED` | error | Marker end line does not match its open marker. |
| `UCP_MARKER_END_WITHOUT_START` | error | Marker end line has no matching start. |
| `UCP_MARKER_FORBIDDEN_PAYLOAD` | error | Marker line carries a forbidden payload. |
| `UCP_MARKER_MALFORMED` | error | Marker line is malformed. |
| `UCP_MARKER_NESTED_SPAN` | error | Marker spans may not be nested. |
| `UCP_MARKER_UNSUPPORTED_INFERENCE` | error | Marker span uses an unsupported inference. |

## Binding registry

| Code | Severity | Message |
|---|---|---|
| `UCP_REGISTRY_DUPLICATE_REGISTRATION` | error | Duplicate registration in the binding registry. |
| `UCP_REGISTRY_JSON_PARSE` | error | Binding registry is not valid JSON. |
| `UCP_REGISTRY_ROW_MISSING` | error | Referenced registry row is missing. |
| `UCP_REGISTRY_SCHEMA_INVALID` | error | Binding registry does not match its schema. |
| `UCP_REGISTRY_SLUG_PREFIX_MISMATCH` | error | Binding slug prefix does not match the registry. |
| `UCP_REGISTRY_SLUG_ROW_CONFLICT` | error | Binding slug conflicts with an existing registry row. |

## Evidence ledger

| Code | Severity | Message |
|---|---|---|
| `UCP_EVIDENCE_APPEND_ONLY_VIOLATION` | error | Evidence ledger is append-only; rewrite rejected. |
| `UCP_EVIDENCE_BINDING_SET_HASH_MISMATCH` | error | Evidence binding-set hash does not match. |
| `UCP_EVIDENCE_EXPECTED_HEAD_MISMATCH` | error | Expected head event does not match current head. |
| `UCP_EVIDENCE_IDEMPOTENCY_CONFLICT` | error | Idempotency key was reused with different intent. |
| `UCP_EVIDENCE_INVALID_TRANSITION` | error | Evidence aggregate is not in a state that allows this transition. |
| `UCP_EVIDENCE_JSON_PARSE` | error | Evidence ledger line is not valid JSON. |
| `UCP_EVIDENCE_LEDGER_DAMAGED` | error | Refusing to append to damaged evidence history. |
| `UCP_EVIDENCE_LOCK_TIMEOUT` | error | Timed out acquiring evidence append lock. |
| `UCP_EVIDENCE_PRODUCER_NOT_TRUSTED` | error | Evidence producer is not trusted. |
| `UCP_EVIDENCE_ROW_MISSING` | error | Referenced evidence row is missing. |
| `UCP_EVIDENCE_SCHEMA_INVALID` | error | Evidence event does not match its schema. |
| `UCP_EVIDENCE_VERIFICATION_NOT_PASS` | error | Evidence verification did not pass. |
| `UCP_LEDGER_CHAIN_BROKEN` | error | Evidence ledger hash chain is broken: an entry's previous_entry_hash does not match the preceding entry. |
| `UCP_LEDGER_DUPLICATE_INDEX` | error | Evidence ledger contains a duplicate entry_index. |
| `UCP_LEDGER_INDEX_GAP` | error | Evidence ledger entry_index does not match its actual position (gap, reorder, or truncation). |

## Signature / proof verification

| Code | Severity | Message |
|---|---|---|
| `UCP_SIGNATURE_ALG_UNSUPPORTED` | error | Proof signature algorithm is unsupported. |
| `UCP_SIGNATURE_BAD` | error | Proof signature is invalid. |
| `UCP_SIGNATURE_MISSING` | error | Proof event is missing a signature. |
| `UCP_SIGNATURE_UNKNOWN_KEY_ID` | error | Proof signature references an unknown key id. |

## Swift function recognizer

| Code | Severity | Message |
|---|---|---|
| `UCP_SWIFT_CONDITIONAL_COMPILATION` | error | Conditional compilation directive inside a marked span. |
| `UCP_SWIFT_FUNC_NO_BODY` | error | Marked function has no body. |
| `UCP_SWIFT_FUNC_NO_CLOSING_BRACE` | error | Marked function body has no closing brace. |
| `UCP_SWIFT_MARKER_INSIDE_ATTACHED` | error | Marker is inside an attached declaration. |
| `UCP_SWIFT_MARKER_INSIDE_SPAN` | error | Another marker appears inside a marked span. |
| `UCP_SWIFT_MARKER_NOT_ADJACENT` | error | Marker is not adjacent to a declaration. |
| `UCP_SWIFT_MULTIPLE_CANDIDATES` | error | Multiple candidate declarations for the marker. |
| `UCP_SWIFT_NESTED_FUNC_UNSUPPORTED` | error | Nested functions are unsupported in a marked span. |
| `UCP_SWIFT_NEXT_NODE_NOT_FUNC` | error | The node following the marker is not a function. |
| `UCP_SWIFT_NO_PARSER` | error | No Swift parser is available. |
| `UCP_SWIFT_PARSE_ERROR` | error | Swift parse error within the marker region. |

## Workspace config

| Code | Severity | Message |
|---|---|---|
| `UCP_WORKSPACE_COMPONENT_UNKNOWN` | error | Unknown component '...'; does not match the declared component. |
| `UCP_WORKSPACE_CONFIG_INVALID` | error | Invalid use-cases-plugin.yml. |
| `UCP_WORKSPACE_CONFIG_PARSE` | error | Unable to parse use-cases-plugin.yml. |

## Migration

| Code | Severity | Message |
|---|---|---|
| `UCP_MIGRATION_UNSAFE_OUTPUT_PATH` | error | Migration output path must stay inside the data root. |
| `UCP_MIGRATION_UNSAFE_SOURCE_PATH` | error | Migration source path must stay inside the repository. |

## Showcase lifecycle

| Code | Severity | Message |
|---|---|---|
| `UCP_SHOWCASE_FAILURE_DECISION_REQUIRED` | error | Cannot finish until each failed or blocked verdict has a failure decision. |
| `UCP_SHOWCASE_FINISH_REQUIRED` | error | User approval/rejection requires a finished showcase run. |
| `UCP_SHOWCASE_IDEMPOTENCY_CONFLICT` | error | Idempotency key was reused with different intent. |
| `UCP_SHOWCASE_INVALID_CORRECTION_TARGET` | error | Correction target must be a verdict event. |
| `UCP_SHOWCASE_INVALID_FAILURE_DECISION_TARGET` | error | Failure decision target must be a failed or blocked verdict event. |
| `UCP_SHOWCASE_KNOWN_GAP_ACK_REQUIRED` | error | Partial plan requires known-gap acknowledgement. |
| `UCP_SHOWCASE_LEDGER_DAMAGED` | error | Refusing to append to damaged showcase history. |
| `UCP_SHOWCASE_PLAN_HASH_MISMATCH` | error | Plan content hash does not match plan body. |
| `UCP_SHOWCASE_PLAN_INVALID` | error | Presentation plan file is not a v1 plan. |
| `UCP_SHOWCASE_PLAN_PLACEHOLDER_HASH` | error | Plan content hash must not be a placeholder. |
| `UCP_SHOWCASE_PLAN_UNREADABLE` | error | Presentation plan file could not be read. |
| `UCP_SHOWCASE_RUN_ID_CONFLICT` | error | Showcase run id already exists. |
| `UCP_SHOWCASE_TRUSTED_CONFIRMATION_REQUIRED` | error | User approval requires a trusted interactive user confirmation path. |
| `UCP_SHOWCASE_USER_APPROVAL_REQUIRED` | error | Agent cannot record user-required approval. |
| `UCP_SHOWCASE_VERDICT_REQUIRES_OBSERVATION` | error | Verdict requires a prior observation. |

## Path safety

| Code | Severity | Message |
|---|---|---|
| `UCP_INVALID_ID` | error | Identifier is not a canonical id; refusing to use it as a path segment. |
| `UCP_PATH_ESCAPE` | error | Unsafe relative path escapes its root boundary. |

// Centralized, stable `UCP_*` error-code registry (additive).
//
// This module is the single source of truth for the public error codes that are
// part of the v1 contract (see `docs/reference/stability.md`). It does NOT
// replace the existing internal enum families or the ~21 `PresentationSkillsError`
// string-literal codes; instead it gives each of them a stable public `UCP_*`
// code and a mapping helper, so diagnostics can be annotated with a stable code
// without renaming every internal call site at once.
//
// The on-disk reference page `docs/reference/error-codes.md` is generated from
// this registry (see `./render.ts` and `scripts/generate-error-codes.mjs`) and a
// test keeps the two in sync.

import { EvidenceErrorCode } from "../markers/evidenceLedger.js";
import { MarkerErrorCode } from "../markers/markerLine.js";
import { SignatureFailureCode } from "../markers/proofSignature.js";
import { RegistryErrorCode } from "../markers/registry.js";
import { SwiftFuncErrorCode } from "../markers/swiftFuncRecognizer.js";

/** Declared severity of an error code. */
export type UcmErrorSeverity = "error" | "warning" | "info";

/** The surface a code originates from (groups codes in the docs + diagnostics). */
export type UcmErrorSurface =
  | "marker"
  | "registry"
  | "evidence"
  | "signature"
  | "swift"
  | "workspace"
  | "migration"
  | "showcase"
  | "path";

/** A single registry entry, keyed by its `UCP_*` code. */
export interface UcmErrorEntry {
  /** Human-readable message template (may contain `'...'` placeholders). */
  readonly message: string;
  readonly severity: UcmErrorSeverity;
  readonly surface: UcmErrorSurface;
  /** Relative docs path, e.g. `errors/UCP_MARKER_MALFORMED`. */
  readonly docs: string;
}

function entry(
  surface: UcmErrorSurface,
  message: string,
  code: string,
  severity: UcmErrorSeverity = "error"
): UcmErrorEntry {
  return { message, severity, surface, docs: `errors/${code}` };
}

// The registry. Keys are the stable public `UCP_*` codes; never rename or remove
// a key without a major version bump (see stability policy).
const REGISTRY = {
  // --- marker grammar (surface: marker) -----------------------------------
  UCP_MARKER_FORBIDDEN_PAYLOAD: entry(
    "marker",
    "Marker line carries a forbidden payload.",
    "UCP_MARKER_FORBIDDEN_PAYLOAD"
  ),
  UCP_MARKER_MALFORMED: entry("marker", "Marker line is malformed.", "UCP_MARKER_MALFORMED"),
  UCP_MARKER_END_MALFORMED: entry(
    "marker",
    "Marker end line is malformed.",
    "UCP_MARKER_END_MALFORMED"
  ),
  UCP_MARKER_END_MISMATCHED: entry(
    "marker",
    "Marker end line does not match its open marker.",
    "UCP_MARKER_END_MISMATCHED"
  ),
  UCP_MARKER_END_WITHOUT_START: entry(
    "marker",
    "Marker end line has no matching start.",
    "UCP_MARKER_END_WITHOUT_START"
  ),
  UCP_MARKER_UNSUPPORTED_INFERENCE: entry(
    "marker",
    "Marker span uses an unsupported inference.",
    "UCP_MARKER_UNSUPPORTED_INFERENCE"
  ),
  UCP_MARKER_NESTED_SPAN: entry(
    "marker",
    "Marker spans may not be nested.",
    "UCP_MARKER_NESTED_SPAN"
  ),
  UCP_MARKER_DUPLICATE_BINDING_SLUG: entry(
    "marker",
    "Duplicate binding slug within the same source.",
    "UCP_MARKER_DUPLICATE_BINDING_SLUG"
  ),

  // --- binding registry (surface: registry) -------------------------------
  UCP_REGISTRY_JSON_PARSE: entry(
    "registry",
    "Binding registry is not valid JSON.",
    "UCP_REGISTRY_JSON_PARSE"
  ),
  UCP_REGISTRY_SCHEMA_INVALID: entry(
    "registry",
    "Binding registry does not match its schema.",
    "UCP_REGISTRY_SCHEMA_INVALID"
  ),
  UCP_REGISTRY_SLUG_PREFIX_MISMATCH: entry(
    "registry",
    "Binding slug prefix does not match the registry.",
    "UCP_REGISTRY_SLUG_PREFIX_MISMATCH"
  ),
  UCP_REGISTRY_ROW_MISSING: entry(
    "registry",
    "Referenced registry row is missing.",
    "UCP_REGISTRY_ROW_MISSING"
  ),
  UCP_REGISTRY_DUPLICATE_REGISTRATION: entry(
    "registry",
    "Duplicate registration in the binding registry.",
    "UCP_REGISTRY_DUPLICATE_REGISTRATION"
  ),
  UCP_REGISTRY_SLUG_ROW_CONFLICT: entry(
    "registry",
    "Binding slug conflicts with an existing registry row.",
    "UCP_REGISTRY_SLUG_ROW_CONFLICT"
  ),

  // --- evidence ledger (surface: evidence) --------------------------------
  UCP_EVIDENCE_JSON_PARSE: entry(
    "evidence",
    "Evidence ledger line is not valid JSON.",
    "UCP_EVIDENCE_JSON_PARSE"
  ),
  UCP_EVIDENCE_SCHEMA_INVALID: entry(
    "evidence",
    "Evidence event does not match its schema.",
    "UCP_EVIDENCE_SCHEMA_INVALID"
  ),
  UCP_EVIDENCE_PRODUCER_NOT_TRUSTED: entry(
    "evidence",
    "Evidence producer is not trusted.",
    "UCP_EVIDENCE_PRODUCER_NOT_TRUSTED"
  ),
  UCP_EVIDENCE_VERIFICATION_NOT_PASS: entry(
    "evidence",
    "Evidence verification did not pass.",
    "UCP_EVIDENCE_VERIFICATION_NOT_PASS"
  ),
  UCP_EVIDENCE_BINDING_SET_HASH_MISMATCH: entry(
    "evidence",
    "Evidence binding-set hash does not match.",
    "UCP_EVIDENCE_BINDING_SET_HASH_MISMATCH"
  ),
  UCP_EVIDENCE_ROW_MISSING: entry(
    "evidence",
    "Referenced evidence row is missing.",
    "UCP_EVIDENCE_ROW_MISSING"
  ),
  UCP_EVIDENCE_APPEND_ONLY_VIOLATION: entry(
    "evidence",
    "Evidence ledger is append-only; rewrite rejected.",
    "UCP_EVIDENCE_APPEND_ONLY_VIOLATION"
  ),
  UCP_EVIDENCE_LEDGER_DAMAGED: entry(
    "evidence",
    "Refusing to append to damaged evidence history.",
    "UCP_EVIDENCE_LEDGER_DAMAGED"
  ),
  UCP_EVIDENCE_IDEMPOTENCY_CONFLICT: entry(
    "evidence",
    "Idempotency key was reused with different intent.",
    "UCP_EVIDENCE_IDEMPOTENCY_CONFLICT"
  ),
  UCP_EVIDENCE_INVALID_TRANSITION: entry(
    "evidence",
    "Evidence aggregate is not in a state that allows this transition.",
    "UCP_EVIDENCE_INVALID_TRANSITION"
  ),
  UCP_EVIDENCE_EXPECTED_HEAD_MISMATCH: entry(
    "evidence",
    "Expected head event does not match current head.",
    "UCP_EVIDENCE_EXPECTED_HEAD_MISMATCH"
  ),
  UCP_EVIDENCE_LOCK_TIMEOUT: entry(
    "evidence",
    "Timed out acquiring evidence append lock.",
    "UCP_EVIDENCE_LOCK_TIMEOUT"
  ),

  // --- tamper-evident hash chain (surface: evidence) ----------------------
  UCP_LEDGER_CHAIN_BROKEN: entry(
    "evidence",
    "Evidence ledger hash chain is broken: an entry's previous_entry_hash does not match the preceding entry.",
    "UCP_LEDGER_CHAIN_BROKEN"
  ),
  UCP_LEDGER_INDEX_GAP: entry(
    "evidence",
    "Evidence ledger entry_index does not match its actual position (gap, reorder, or truncation).",
    "UCP_LEDGER_INDEX_GAP"
  ),
  UCP_LEDGER_DUPLICATE_INDEX: entry(
    "evidence",
    "Evidence ledger contains a duplicate entry_index.",
    "UCP_LEDGER_DUPLICATE_INDEX"
  ),

  // --- signature / proof verification (surface: signature) ----------------
  UCP_SIGNATURE_MISSING: entry(
    "signature",
    "Proof event is missing a signature.",
    "UCP_SIGNATURE_MISSING"
  ),
  UCP_SIGNATURE_ALG_UNSUPPORTED: entry(
    "signature",
    "Proof signature algorithm is unsupported.",
    "UCP_SIGNATURE_ALG_UNSUPPORTED"
  ),
  UCP_SIGNATURE_UNKNOWN_KEY_ID: entry(
    "signature",
    "Proof signature references an unknown key id.",
    "UCP_SIGNATURE_UNKNOWN_KEY_ID"
  ),
  UCP_SIGNATURE_BAD: entry("signature", "Proof signature is invalid.", "UCP_SIGNATURE_BAD"),

  // --- swift function recognizer (surface: swift) -------------------------
  UCP_SWIFT_NO_PARSER: entry("swift", "No Swift parser is available.", "UCP_SWIFT_NO_PARSER"),
  UCP_SWIFT_PARSE_ERROR: entry(
    "swift",
    "Swift parse error within the marker region.",
    "UCP_SWIFT_PARSE_ERROR"
  ),
  UCP_SWIFT_MARKER_NOT_ADJACENT: entry(
    "swift",
    "Marker is not adjacent to a declaration.",
    "UCP_SWIFT_MARKER_NOT_ADJACENT"
  ),
  UCP_SWIFT_MARKER_INSIDE_ATTACHED: entry(
    "swift",
    "Marker is inside an attached declaration.",
    "UCP_SWIFT_MARKER_INSIDE_ATTACHED"
  ),
  UCP_SWIFT_NEXT_NODE_NOT_FUNC: entry(
    "swift",
    "The node following the marker is not a function.",
    "UCP_SWIFT_NEXT_NODE_NOT_FUNC"
  ),
  UCP_SWIFT_FUNC_NO_BODY: entry(
    "swift",
    "Marked function has no body.",
    "UCP_SWIFT_FUNC_NO_BODY"
  ),
  UCP_SWIFT_FUNC_NO_CLOSING_BRACE: entry(
    "swift",
    "Marked function body has no closing brace.",
    "UCP_SWIFT_FUNC_NO_CLOSING_BRACE"
  ),
  UCP_SWIFT_NESTED_FUNC_UNSUPPORTED: entry(
    "swift",
    "Nested functions are unsupported in a marked span.",
    "UCP_SWIFT_NESTED_FUNC_UNSUPPORTED"
  ),
  UCP_SWIFT_CONDITIONAL_COMPILATION: entry(
    "swift",
    "Conditional compilation directive inside a marked span.",
    "UCP_SWIFT_CONDITIONAL_COMPILATION"
  ),
  UCP_SWIFT_MARKER_INSIDE_SPAN: entry(
    "swift",
    "Another marker appears inside a marked span.",
    "UCP_SWIFT_MARKER_INSIDE_SPAN"
  ),
  UCP_SWIFT_MULTIPLE_CANDIDATES: entry(
    "swift",
    "Multiple candidate declarations for the marker.",
    "UCP_SWIFT_MULTIPLE_CANDIDATES"
  ),

  // --- workspace config (surface: workspace) ------------------------------
  UCP_WORKSPACE_COMPONENT_UNKNOWN: entry(
    "workspace",
    "Unknown component '...'; does not match the declared component.",
    "UCP_WORKSPACE_COMPONENT_UNKNOWN"
  ),
  UCP_WORKSPACE_CONFIG_PARSE: entry(
    "workspace",
    "Unable to parse use-cases-plugin.yml.",
    "UCP_WORKSPACE_CONFIG_PARSE"
  ),
  UCP_WORKSPACE_CONFIG_INVALID: entry(
    "workspace",
    "Invalid use-cases-plugin.yml.",
    "UCP_WORKSPACE_CONFIG_INVALID"
  ),

  // --- path safety (surface: path) ----------------------------------------
  UCP_PATH_ESCAPE: entry(
    "path",
    "Unsafe relative path escapes its root boundary.",
    "UCP_PATH_ESCAPE"
  ),
  UCP_INVALID_ID: entry(
    "path",
    "Identifier is not a canonical id; refusing to use it as a path segment.",
    "UCP_INVALID_ID"
  ),

  // --- migration test matrix (surface: migration) -------------------------
  UCP_MIGRATION_UNSAFE_SOURCE_PATH: entry(
    "migration",
    "Migration source path must stay inside the repository.",
    "UCP_MIGRATION_UNSAFE_SOURCE_PATH"
  ),
  UCP_MIGRATION_UNSAFE_OUTPUT_PATH: entry(
    "migration",
    "Migration output path must stay inside the data root.",
    "UCP_MIGRATION_UNSAFE_OUTPUT_PATH"
  ),

  // --- showcase lifecycle (surface: showcase) -----------------------------
  UCP_SHOWCASE_PLAN_UNREADABLE: entry(
    "showcase",
    "Presentation plan file could not be read.",
    "UCP_SHOWCASE_PLAN_UNREADABLE"
  ),
  UCP_SHOWCASE_PLAN_PLACEHOLDER_HASH: entry(
    "showcase",
    "Plan content hash must not be a placeholder.",
    "UCP_SHOWCASE_PLAN_PLACEHOLDER_HASH"
  ),
  UCP_SHOWCASE_PLAN_HASH_MISMATCH: entry(
    "showcase",
    "Plan content hash does not match plan body.",
    "UCP_SHOWCASE_PLAN_HASH_MISMATCH"
  ),
  UCP_SHOWCASE_PLAN_INVALID: entry(
    "showcase",
    "Presentation plan file is not a v1 plan.",
    "UCP_SHOWCASE_PLAN_INVALID"
  ),
  UCP_SHOWCASE_USER_APPROVAL_REQUIRED: entry(
    "showcase",
    "Agent cannot record user-required approval.",
    "UCP_SHOWCASE_USER_APPROVAL_REQUIRED"
  ),
  UCP_SHOWCASE_TRUSTED_CONFIRMATION_REQUIRED: entry(
    "showcase",
    "User approval requires a trusted interactive user confirmation path.",
    "UCP_SHOWCASE_TRUSTED_CONFIRMATION_REQUIRED"
  ),
  UCP_SHOWCASE_FINISH_REQUIRED: entry(
    "showcase",
    "User approval/rejection requires a finished showcase run.",
    "UCP_SHOWCASE_FINISH_REQUIRED"
  ),
  UCP_SHOWCASE_KNOWN_GAP_ACK_REQUIRED: entry(
    "showcase",
    "Partial plan requires known-gap acknowledgement.",
    "UCP_SHOWCASE_KNOWN_GAP_ACK_REQUIRED"
  ),
  UCP_SHOWCASE_LEDGER_DAMAGED: entry(
    "showcase",
    "Refusing to append to damaged showcase history.",
    "UCP_SHOWCASE_LEDGER_DAMAGED"
  ),
  UCP_SHOWCASE_IDEMPOTENCY_CONFLICT: entry(
    "showcase",
    "Idempotency key was reused with different intent.",
    "UCP_SHOWCASE_IDEMPOTENCY_CONFLICT"
  ),
  UCP_SHOWCASE_RUN_ID_CONFLICT: entry(
    "showcase",
    "Showcase run id already exists.",
    "UCP_SHOWCASE_RUN_ID_CONFLICT"
  ),
  UCP_SHOWCASE_VERDICT_REQUIRES_OBSERVATION: entry(
    "showcase",
    "Verdict requires a prior observation.",
    "UCP_SHOWCASE_VERDICT_REQUIRES_OBSERVATION"
  ),
  UCP_SHOWCASE_INVALID_FAILURE_DECISION_TARGET: entry(
    "showcase",
    "Failure decision target must be a failed or blocked verdict event.",
    "UCP_SHOWCASE_INVALID_FAILURE_DECISION_TARGET"
  ),
  UCP_SHOWCASE_FAILURE_DECISION_REQUIRED: entry(
    "showcase",
    "Cannot finish until each failed or blocked verdict has a failure decision.",
    "UCP_SHOWCASE_FAILURE_DECISION_REQUIRED"
  ),
  UCP_SHOWCASE_INVALID_CORRECTION_TARGET: entry(
    "showcase",
    "Correction target must be a verdict event.",
    "UCP_SHOWCASE_INVALID_CORRECTION_TARGET"
  )
} as const satisfies Record<string, UcmErrorEntry>;

/** The typed union of every stable public `UCP_*` error code. */
export type UcmErrorCode = keyof typeof REGISTRY;

/** The single source-of-truth registry of stable `UCP_*` error codes. */
export const UCP_ERROR_REGISTRY: Readonly<Record<UcmErrorCode, UcmErrorEntry>> =
  Object.freeze(REGISTRY);

/** Every `UCP_*` code, in stable (sorted) order. */
export const UCP_ERROR_CODES: readonly UcmErrorCode[] = Object.freeze(
  (Object.keys(REGISTRY) as UcmErrorCode[]).sort()
);

/** Look up a registry entry by its `UCP_*` code. */
export function getUcmErrorEntry(code: UcmErrorCode): UcmErrorEntry {
  return UCP_ERROR_REGISTRY[code];
}

// --- legacy → UCP_* mapping -------------------------------------------------
//
// The five existing enum families, keyed by family. Using
// `Record<<FamilyType>, UcmErrorCode>` makes each map exhaustive over its family
// at compile time — adding a new enum value will fail the build until it is
// mapped here.

/** The legacy enum families covered by the registry. */
export type UcmErrorFamily = "marker" | "registry" | "evidence" | "swiftFunc" | "signature";

export const LEGACY_ENUM_CODE_MAP: {
  readonly marker: Readonly<Record<MarkerErrorCode, UcmErrorCode>>;
  readonly registry: Readonly<Record<RegistryErrorCode, UcmErrorCode>>;
  readonly evidence: Readonly<Record<EvidenceErrorCode, UcmErrorCode>>;
  readonly swiftFunc: Readonly<Record<SwiftFuncErrorCode, UcmErrorCode>>;
  readonly signature: Readonly<Record<SignatureFailureCode, UcmErrorCode>>;
} = Object.freeze({
  marker: Object.freeze({
    FORBIDDEN_MARKER_PAYLOAD: "UCP_MARKER_FORBIDDEN_PAYLOAD",
    MALFORMED_MARKER: "UCP_MARKER_MALFORMED",
    MALFORMED_END_MARKER: "UCP_MARKER_END_MALFORMED",
    MISMATCHED_END_MARKER: "UCP_MARKER_END_MISMATCHED",
    END_WITHOUT_START: "UCP_MARKER_END_WITHOUT_START",
    UNSUPPORTED_INFERENCE: "UCP_MARKER_UNSUPPORTED_INFERENCE",
    NESTED_SPAN: "UCP_MARKER_NESTED_SPAN",
    DUPLICATE_BINDING_SLUG: "UCP_MARKER_DUPLICATE_BINDING_SLUG"
  }),
  registry: Object.freeze({
    JSON_PARSE_ERROR: "UCP_REGISTRY_JSON_PARSE",
    REGISTRY_SCHEMA_INVALID: "UCP_REGISTRY_SCHEMA_INVALID",
    SLUG_PREFIX_MISMATCH: "UCP_REGISTRY_SLUG_PREFIX_MISMATCH",
    REGISTRY_ROW_MISSING: "UCP_REGISTRY_ROW_MISSING",
    DUPLICATE_REGISTRATION: "UCP_REGISTRY_DUPLICATE_REGISTRATION",
    SLUG_ROW_CONFLICT: "UCP_REGISTRY_SLUG_ROW_CONFLICT"
  }),
  evidence: Object.freeze({
    JSON_PARSE_ERROR: "UCP_EVIDENCE_JSON_PARSE",
    EVIDENCE_SCHEMA_INVALID: "UCP_EVIDENCE_SCHEMA_INVALID",
    SIGNATURE_MISSING: "UCP_SIGNATURE_MISSING",
    SIGNATURE_ALG_UNSUPPORTED: "UCP_SIGNATURE_ALG_UNSUPPORTED",
    UNKNOWN_KEY_ID: "UCP_SIGNATURE_UNKNOWN_KEY_ID",
    BAD_SIGNATURE: "UCP_SIGNATURE_BAD",
    PRODUCER_NOT_TRUSTED: "UCP_EVIDENCE_PRODUCER_NOT_TRUSTED",
    VERIFICATION_NOT_PASS: "UCP_EVIDENCE_VERIFICATION_NOT_PASS",
    BINDING_SET_HASH_MISMATCH: "UCP_EVIDENCE_BINDING_SET_HASH_MISMATCH",
    EVIDENCE_ROW_MISSING: "UCP_EVIDENCE_ROW_MISSING",
    APPEND_ONLY_VIOLATION: "UCP_EVIDENCE_APPEND_ONLY_VIOLATION"
  }),
  swiftFunc: Object.freeze({
    NO_SWIFT_PARSER: "UCP_SWIFT_NO_PARSER",
    SWIFT_PARSE_ERROR_IN_REGION: "UCP_SWIFT_PARSE_ERROR",
    MARKER_NOT_ADJACENT_TO_DECLARATION: "UCP_SWIFT_MARKER_NOT_ADJACENT",
    MARKER_INSIDE_ATTACHED_DECLARATION: "UCP_SWIFT_MARKER_INSIDE_ATTACHED",
    NEXT_NODE_NOT_FUNC: "UCP_SWIFT_NEXT_NODE_NOT_FUNC",
    FUNC_HAS_NO_BODY: "UCP_SWIFT_FUNC_NO_BODY",
    FUNC_BODY_HAS_NO_CLOSING_BRACE: "UCP_SWIFT_FUNC_NO_CLOSING_BRACE",
    NESTED_FUNC_UNSUPPORTED: "UCP_SWIFT_NESTED_FUNC_UNSUPPORTED",
    CONDITIONAL_COMPILATION_IN_SPAN: "UCP_SWIFT_CONDITIONAL_COMPILATION",
    ANOTHER_MARKER_INSIDE_SPAN: "UCP_SWIFT_MARKER_INSIDE_SPAN",
    MULTIPLE_CANDIDATE_DECLARATIONS: "UCP_SWIFT_MULTIPLE_CANDIDATES"
  }),
  signature: Object.freeze({
    SIGNATURE_MISSING: "UCP_SIGNATURE_MISSING",
    SIGNATURE_ALG_UNSUPPORTED: "UCP_SIGNATURE_ALG_UNSUPPORTED",
    UNKNOWN_KEY_ID: "UCP_SIGNATURE_UNKNOWN_KEY_ID",
    BAD_SIGNATURE: "UCP_SIGNATURE_BAD"
  })
});

/**
 * Map an existing internal enum value to its stable `UCP_*` public code.
 * The `family` selects which enum the code belongs to (the same legacy string,
 * e.g. `SIGNATURE_MISSING`, exists in more than one family).
 */
export function mapEnumCode(family: "marker", code: MarkerErrorCode): UcmErrorCode;
export function mapEnumCode(family: "registry", code: RegistryErrorCode): UcmErrorCode;
export function mapEnumCode(family: "evidence", code: EvidenceErrorCode): UcmErrorCode;
export function mapEnumCode(family: "swiftFunc", code: SwiftFuncErrorCode): UcmErrorCode;
export function mapEnumCode(family: "signature", code: SignatureFailureCode): UcmErrorCode;
export function mapEnumCode(family: UcmErrorFamily, code: string): UcmErrorCode {
  const familyMap = LEGACY_ENUM_CODE_MAP[family] as Record<string, UcmErrorCode>;
  const mapped = familyMap[code];
  if (!mapped) {
    throw new Error(`No UCP_* code mapped for ${family} code '${code}'.`);
  }
  return mapped;
}

/**
 * Map a legacy `PresentationSkillsError` string-literal code to its stable
 * `UCP_*` public code. Returns `undefined` for unmapped/unknown codes.
 */
export const LEGACY_STRING_CODE_MAP: Readonly<Record<string, UcmErrorCode>> = Object.freeze({
  "component.unknown": "UCP_WORKSPACE_COMPONENT_UNKNOWN",
  "workspace_config.parse_error": "UCP_WORKSPACE_CONFIG_PARSE",
  "workspace_config.schema_error": "UCP_WORKSPACE_CONFIG_INVALID",
  "path.escape": "UCP_PATH_ESCAPE",
  "path.invalid_id": "UCP_INVALID_ID",
  migration_unsafe_source_path: "UCP_MIGRATION_UNSAFE_SOURCE_PATH",
  migration_unsafe_output_path: "UCP_MIGRATION_UNSAFE_OUTPUT_PATH",
  showcase_plan_file_unreadable: "UCP_SHOWCASE_PLAN_UNREADABLE",
  showcase_plan_placeholder_hash: "UCP_SHOWCASE_PLAN_PLACEHOLDER_HASH",
  showcase_plan_hash_mismatch: "UCP_SHOWCASE_PLAN_HASH_MISMATCH",
  showcase_plan_file_invalid: "UCP_SHOWCASE_PLAN_INVALID",
  "showcase.user_required_approval": "UCP_SHOWCASE_USER_APPROVAL_REQUIRED",
  "showcase.trusted_user_confirmation_required": "UCP_SHOWCASE_TRUSTED_CONFIRMATION_REQUIRED",
  "showcase.finish_required_for_approval": "UCP_SHOWCASE_FINISH_REQUIRED",
  evidence_ledger_damaged: "UCP_EVIDENCE_LEDGER_DAMAGED",
  evidence_idempotency_conflict: "UCP_EVIDENCE_IDEMPOTENCY_CONFLICT",
  evidence_invalid_transition: "UCP_EVIDENCE_INVALID_TRANSITION",
  evidence_expected_head_mismatch: "UCP_EVIDENCE_EXPECTED_HEAD_MISMATCH",
  evidence_lock_timeout: "UCP_EVIDENCE_LOCK_TIMEOUT",
  showcase_known_gap_ack_required: "UCP_SHOWCASE_KNOWN_GAP_ACK_REQUIRED",
  showcase_ledger_damaged: "UCP_SHOWCASE_LEDGER_DAMAGED",
  showcase_idempotency_conflict: "UCP_SHOWCASE_IDEMPOTENCY_CONFLICT",
  showcase_run_id_conflict: "UCP_SHOWCASE_RUN_ID_CONFLICT",
  showcase_verdict_requires_observation: "UCP_SHOWCASE_VERDICT_REQUIRES_OBSERVATION",
  showcase_invalid_failure_decision_target: "UCP_SHOWCASE_INVALID_FAILURE_DECISION_TARGET",
  showcase_failure_decision_required: "UCP_SHOWCASE_FAILURE_DECISION_REQUIRED",
  showcase_invalid_correction_target: "UCP_SHOWCASE_INVALID_CORRECTION_TARGET"
});

/** Map a legacy string-literal diagnostic code to its `UCP_*` code, if known. */
export function mapStringCode(code: string): UcmErrorCode | undefined {
  return LEGACY_STRING_CODE_MAP[code];
}

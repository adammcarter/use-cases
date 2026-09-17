/// The surface a public code originates from. Declaration order is the order
/// the reference page lists them in (`SURFACE_ORDER` in render.ts).
public enum PublicErrorSurface: String, CaseIterable, Sendable {
  case marker
  case registry
  case evidence
  case signature
  case swift
  case workspace
  case migration
  case showcase
  case path

  /// The section heading on the reference page.
  public var title: String {
    switch self {
    case .marker: "Marker grammar"
    case .registry: "Binding registry"
    case .evidence: "Evidence ledger"
    case .signature: "Signature / proof verification"
    case .swift: "Swift function recognizer"
    case .workspace: "Workspace config"
    case .migration: "Migration"
    case .showcase: "Showcase lifecycle"
    case .path: "Path safety"
    }
  }
}

/// One registry entry.
public struct PublicErrorEntry: Sendable, Equatable {
  public let code: PublicErrorCode
  /// Human-readable message template (may contain `'...'` placeholders).
  public let message: String
  public let severity: DiagnosticSeverity
  public let surface: PublicErrorSurface
  /// Relative docs path, e.g. `errors/UCM_MARKER_MALFORMED`.
  public let documentationPath: String

  init(
    _ code: PublicErrorCode,
    _ surface: PublicErrorSurface,
    _ message: String,
    severity: DiagnosticSeverity = .error,
  ) {
    self.code = code
    self.message = message
    self.severity = severity
    self.surface = surface
    documentationPath = "errors/\(code.rawValue)"
  }
}

/// The single source of truth for the stable public error codes
/// (packages/core/src/errors/registry.ts).
public enum PublicErrorRegistry {
  /// Every entry, in the TypeScript registry's declaration order. Never rename
  /// or remove one without a major version bump (docs/reference/stability.md).
  public static let entries: [PublicErrorEntry] = [
    PublicErrorEntry(.markerForbiddenPayload, .marker, "Marker line carries a forbidden payload."),
    PublicErrorEntry(.markerMalformed, .marker, "Marker line is malformed."),
    PublicErrorEntry(.markerEndMalformed, .marker, "Marker end line is malformed."),
    PublicErrorEntry(
      .markerEndMismatched,
      .marker,
      "Marker end line does not match its open marker.",
    ),
    PublicErrorEntry(.markerEndWithoutStart, .marker, "Marker end line has no matching start."),
    PublicErrorEntry(
      .markerUnsupportedInference,
      .marker,
      "Marker span uses an unsupported inference.",
    ),
    PublicErrorEntry(.markerNestedSpan, .marker, "Marker spans may not be nested."),
    PublicErrorEntry(
      .markerUnbalancedIgnore,
      .marker,
      "Marker ignore region is unbalanced or nested.",
    ),
    PublicErrorEntry(
      .markerDuplicateBindingSlug,
      .marker,
      "Duplicate binding slug within the same source.",
    ),
    PublicErrorEntry(.registryJSONParse, .registry, "Binding registry is not valid JSON."),
    PublicErrorEntry(
      .registrySchemaInvalid,
      .registry,
      "Binding registry does not match its schema.",
    ),
    PublicErrorEntry(
      .registrySlugPrefixMismatch,
      .registry,
      "Binding slug prefix does not match the registry.",
    ),
    PublicErrorEntry(.registryRowMissing, .registry, "Referenced registry row is missing."),
    PublicErrorEntry(
      .registryDuplicateRegistration,
      .registry,
      "Duplicate registration in the binding registry.",
    ),
    PublicErrorEntry(
      .registrySlugRowConflict,
      .registry,
      "Binding slug conflicts with an existing registry row.",
    ),
    PublicErrorEntry(
      .registryReleaseWithoutRegistration,
      .registry,
      "Binding release names a slug that is not currently registered.",
    ),
    PublicErrorEntry(.evidenceJSONParse, .evidence, "Evidence ledger line is not valid JSON."),
    PublicErrorEntry(
      .evidenceSchemaInvalid,
      .evidence,
      "Evidence event does not match its schema.",
    ),
    PublicErrorEntry(.evidenceProducerNotTrusted, .evidence, "Evidence producer is not trusted."),
    PublicErrorEntry(
      .evidenceVerificationNotPass,
      .evidence,
      "Evidence verification did not pass.",
    ),
    PublicErrorEntry(
      .evidenceBindingSetHashMismatch,
      .evidence,
      "Evidence binding-set hash does not match.",
    ),
    PublicErrorEntry(.evidenceRowMissing, .evidence, "Referenced evidence row is missing."),
    PublicErrorEntry(
      .evidenceAppendOnlyViolation,
      .evidence,
      "Evidence ledger is append-only; rewrite rejected.",
    ),
    PublicErrorEntry(
      .evidenceLedgerDamaged,
      .evidence,
      "Refusing to append to damaged evidence history.",
    ),
    PublicErrorEntry(
      .evidenceIdempotencyConflict,
      .evidence,
      "Idempotency key was reused with different intent.",
    ),
    PublicErrorEntry(
      .evidenceInvalidTransition,
      .evidence,
      "Evidence aggregate is not in a state that allows this transition.",
    ),
    PublicErrorEntry(
      .evidenceExpectedHeadMismatch,
      .evidence,
      "Expected head event does not match current head.",
    ),
    PublicErrorEntry(.evidenceLockTimeout, .evidence, "Timed out acquiring evidence append lock."),
    PublicErrorEntry(
      .ledgerChainBroken,
      .evidence,
      "Evidence ledger hash chain is broken: an entry's previous_entry_hash does not "
        + "match the preceding entry.",
    ),
    PublicErrorEntry(
      .ledgerIndexGap,
      .evidence,
      "Evidence ledger entry_index does not match its actual position (gap, reorder, "
        + "or truncation).",
    ),
    PublicErrorEntry(
      .ledgerDuplicateIndex,
      .evidence,
      "Evidence ledger contains a duplicate entry_index.",
    ),
    PublicErrorEntry(.signatureMissing, .signature, "Proof event is missing a signature."),
    PublicErrorEntry(
      .signatureAlgorithmUnsupported,
      .signature,
      "Proof signature algorithm is unsupported.",
    ),
    PublicErrorEntry(
      .signatureUnknownKeyIdentifier,
      .signature,
      "Proof signature references an unknown key id.",
    ),
    PublicErrorEntry(.signatureBad, .signature, "Proof signature is invalid."),
    PublicErrorEntry(.swiftNoParser, .swift, "No Swift parser is available."),
    PublicErrorEntry(.swiftParseError, .swift, "Swift parse error within the marker region."),
    PublicErrorEntry(.swiftMarkerNotAdjacent, .swift, "Marker is not adjacent to a declaration."),
    PublicErrorEntry(
      .swiftMarkerInsideAttached,
      .swift,
      "Marker is inside an attached declaration.",
    ),
    PublicErrorEntry(
      .swiftNextNodeNotFunction,
      .swift,
      "The node following the marker is not a function.",
    ),
    PublicErrorEntry(.swiftFunctionNoBody, .swift, "Marked function has no body."),
    PublicErrorEntry(
      .swiftFunctionNoClosingBrace,
      .swift,
      "Marked function body has no closing brace.",
    ),
    PublicErrorEntry(
      .swiftNestedFunctionUnsupported,
      .swift,
      "Nested functions are unsupported in a marked span.",
    ),
    PublicErrorEntry(
      .swiftConditionalCompilation,
      .swift,
      "Conditional compilation directive inside a marked span.",
    ),
    PublicErrorEntry(
      .swiftMarkerInsideSpan,
      .swift,
      "Another marker appears inside a marked span.",
    ),
    PublicErrorEntry(
      .swiftMultipleCandidates,
      .swift,
      "Multiple candidate declarations for the marker.",
    ),
    PublicErrorEntry(
      .workspaceComponentUnknown,
      .workspace,
      "Unknown component '...'; does not match the declared component.",
    ),
    PublicErrorEntry(.workspaceConfigParse, .workspace, "Unable to parse use-cases.yml."),
    PublicErrorEntry(.workspaceConfigInvalid, .workspace, "Invalid use-cases.yml."),
    PublicErrorEntry(.pathEscape, .path, "Unsafe relative path escapes its root boundary."),
    PublicErrorEntry(
      .invalidIdentifier,
      .path,
      "Identifier is not a canonical id; refusing to use it as a path segment.",
    ),
    PublicErrorEntry(
      .migrationUnsafeSourcePath,
      .migration,
      "Migration source path must stay inside the repository.",
    ),
    PublicErrorEntry(
      .migrationUnsafeOutputPath,
      .migration,
      "Migration output path must stay inside the data root.",
    ),
    PublicErrorEntry(
      .showcasePlanUnreadable,
      .showcase,
      "Presentation plan file could not be read.",
    ),
    PublicErrorEntry(
      .showcasePlanPlaceholderHash,
      .showcase,
      "Plan content hash must not be a placeholder.",
    ),
    PublicErrorEntry(
      .showcasePlanHashMismatch,
      .showcase,
      "Plan content hash does not match plan body.",
    ),
    PublicErrorEntry(.showcasePlanInvalid, .showcase, "Presentation plan file is not a v1 plan."),
    PublicErrorEntry(
      .showcaseUserApprovalRequired,
      .showcase,
      "Agent cannot record user-required approval.",
    ),
    PublicErrorEntry(
      .showcaseTrustedConfirmationRequired,
      .showcase,
      "User approval requires a trusted interactive user confirmation path.",
    ),
    PublicErrorEntry(
      .showcaseFinishRequired,
      .showcase,
      "User approval/rejection requires a finished showcase run.",
    ),
    PublicErrorEntry(
      .showcaseKnownGapAcknowledgementRequired,
      .showcase,
      "Partial plan requires known-gap acknowledgement.",
    ),
    PublicErrorEntry(
      .showcaseLedgerDamaged,
      .showcase,
      "Refusing to append to damaged showcase history.",
    ),
    PublicErrorEntry(
      .showcaseIdempotencyConflict,
      .showcase,
      "Idempotency key was reused with different intent.",
    ),
    PublicErrorEntry(.showcaseRunIdentifierConflict, .showcase, "Showcase run id already exists."),
    PublicErrorEntry(
      .showcaseVerdictRequiresObservation,
      .showcase,
      "Verdict requires a prior observation.",
    ),
    PublicErrorEntry(
      .showcaseInvalidFailureDecisionTarget,
      .showcase,
      "Failure decision target must be a failed or blocked verdict event.",
    ),
    PublicErrorEntry(
      .showcaseFailureDecisionRequired,
      .showcase,
      "Cannot finish until each failed or blocked verdict has a failure decision.",
    ),
    PublicErrorEntry(
      .showcaseInvalidCorrectionTarget,
      .showcase,
      "Correction target must be a verdict event.",
    ),
  ]

  /// Every code, in `Object.keys(REGISTRY).sort()` order: a bare sort, so
  /// UTF-16 code units (`UCM_INVALID_ID` before `UCM_LEDGER_*`).
  public static let codes: [PublicErrorCode] = entries.map(\.code).sorted { left, right in
    JavaScriptString.precedes(left.rawValue, right.rawValue)
  }

  /// `getUcmErrorEntry`: the entry for `code`. Every code has one; the
  /// registry test proves it.
  public static func entry(for code: PublicErrorCode) -> PublicErrorEntry? {
    entriesByCode[code]
  }

  private static let entriesByCode: [PublicErrorCode: PublicErrorEntry] = Dictionary(
    uniqueKeysWithValues: entries.map { entry in
      (entry.code, entry)
    },
  )
}

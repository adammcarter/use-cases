/// The map from internal codes to stable public codes
/// (`LEGACY_ENUM_CODE_MAP` and `LEGACY_STRING_CODE_MAP` in registry.ts).
///
/// The TypeScript keys each enum family by its string code and relies on the
/// compiler for exhaustiveness. Here each family is keyed by its Swift enum,
/// and exhaustiveness is proved by the registry test over `allCases` against
/// the TypeScript map itself; a lookup answers nil only for a code the test
/// would already have failed on. The same legacy string (`SIGNATURE_MISSING`)
/// exists in more than one family, which the parameter type disambiguates.
public enum PublicErrorCodeMap {
  public static func publicCode(for code: MarkerErrorCode) -> PublicErrorCode? {
    markerCodes[code]
  }

  public static func publicCode(for code: RegistryErrorCode) -> PublicErrorCode? {
    registryCodes[code]
  }

  public static func publicCode(for code: EvidenceErrorCode) -> PublicErrorCode? {
    evidenceCodes[code]
  }

  public static func publicCode(for code: SwiftFunctionErrorCode) -> PublicErrorCode? {
    swiftFunctionCodes[code]
  }

  public static func publicCode(for code: SignatureFailureCode) -> PublicErrorCode? {
    signatureCodes[code]
  }

  /// `mapStringCode`: the public code for a `UseCasesPluginError`-style string
  /// code, or nil for one TypeScript does not map. Matched by exact code units
  /// (``CodeUnitKey``): the code is caller data, not schema-constrained.
  public static func publicCode(forStringCode code: String) -> PublicErrorCode? {
    stringCodeMap[CodeUnitKey(code)]
  }

  /// Every mapped string code, in the TypeScript map's order.
  static let stringCodes: [(code: String, publicCode: PublicErrorCode)] = [
    ("component.unknown", .workspaceComponentUnknown),
    ("workspace_config.parse_error", .workspaceConfigParse),
    ("workspace_config.schema_error", .workspaceConfigInvalid),
    ("path.escape", .pathEscape),
    ("path.invalid_id", .invalidIdentifier),
    ("migration_unsafe_source_path", .migrationUnsafeSourcePath),
    ("migration_unsafe_output_path", .migrationUnsafeOutputPath),
    ("showcase_plan_file_unreadable", .showcasePlanUnreadable),
    ("showcase_plan_placeholder_hash", .showcasePlanPlaceholderHash),
    ("showcase_plan_hash_mismatch", .showcasePlanHashMismatch),
    ("showcase_plan_file_invalid", .showcasePlanInvalid),
    ("showcase.user_required_approval", .showcaseUserApprovalRequired),
    ("showcase.trusted_user_confirmation_required", .showcaseTrustedConfirmationRequired),
    ("showcase.finish_required_for_approval", .showcaseFinishRequired),
    ("evidence_ledger_damaged", .evidenceLedgerDamaged),
    ("evidence_idempotency_conflict", .evidenceIdempotencyConflict),
    ("evidence_invalid_transition", .evidenceInvalidTransition),
    ("evidence_expected_head_mismatch", .evidenceExpectedHeadMismatch),
    ("evidence_lock_timeout", .evidenceLockTimeout),
    ("showcase_known_gap_ack_required", .showcaseKnownGapAcknowledgementRequired),
    ("showcase_ledger_damaged", .showcaseLedgerDamaged),
    ("showcase_idempotency_conflict", .showcaseIdempotencyConflict),
    ("showcase_run_id_conflict", .showcaseRunIdentifierConflict),
    ("showcase_verdict_requires_observation", .showcaseVerdictRequiresObservation),
    ("showcase_invalid_failure_decision_target", .showcaseInvalidFailureDecisionTarget),
    ("showcase_failure_decision_required", .showcaseFailureDecisionRequired),
    ("showcase_invalid_correction_target", .showcaseInvalidCorrectionTarget),
  ]

  private static let stringCodeMap: [CodeUnitKey: PublicErrorCode] = Dictionary(
    uniqueKeysWithValues: stringCodes.map { pair in
      (CodeUnitKey(pair.code), pair.publicCode)
    },
  )

  private static let markerCodes: [MarkerErrorCode: PublicErrorCode] = [
    .forbiddenMarkerPayload: .markerForbiddenPayload,
    .malformedMarker: .markerMalformed,
    .malformedEndMarker: .markerEndMalformed,
    .mismatchedEndMarker: .markerEndMismatched,
    .endWithoutStart: .markerEndWithoutStart,
    .unsupportedInference: .markerUnsupportedInference,
    .nestedSpan: .markerNestedSpan,
    .unbalancedIgnore: .markerUnbalancedIgnore,
    .duplicateBindingSlug: .markerDuplicateBindingSlug,
  ]

  private static let registryCodes: [RegistryErrorCode: PublicErrorCode] = [
    .jsonParseError: .registryJSONParse,
    .registrySchemaInvalid: .registrySchemaInvalid,
    .slugPrefixMismatch: .registrySlugPrefixMismatch,
    .registryRowMissing: .registryRowMissing,
    .duplicateRegistration: .registryDuplicateRegistration,
    .slugRowConflict: .registrySlugRowConflict,
    .releaseWithoutRegistration: .registryReleaseWithoutRegistration,
  ]

  private static let evidenceCodes: [EvidenceErrorCode: PublicErrorCode] = [
    .jsonParseError: .evidenceJSONParse,
    .evidenceSchemaInvalid: .evidenceSchemaInvalid,
    .signatureMissing: .signatureMissing,
    .signatureAlgorithmUnsupported: .signatureAlgorithmUnsupported,
    .unknownKeyIdentifier: .signatureUnknownKeyIdentifier,
    .badSignature: .signatureBad,
    .producerNotTrusted: .evidenceProducerNotTrusted,
    .verificationNotPass: .evidenceVerificationNotPass,
    .bindingSetHashMismatch: .evidenceBindingSetHashMismatch,
    .evidenceRowMissing: .evidenceRowMissing,
    .appendOnlyViolation: .evidenceAppendOnlyViolation,
  ]

  private static let swiftFunctionCodes: [SwiftFunctionErrorCode: PublicErrorCode] = [
    .noSwiftParser: .swiftNoParser,
    .swiftParseErrorInRegion: .swiftParseError,
    .markerNotAdjacentToDeclaration: .swiftMarkerNotAdjacent,
    .markerInsideAttachedDeclaration: .swiftMarkerInsideAttached,
    .nextNodeNotFunction: .swiftNextNodeNotFunction,
    .functionHasNoBody: .swiftFunctionNoBody,
    .functionBodyHasNoClosingBrace: .swiftFunctionNoClosingBrace,
    .nestedFunctionUnsupported: .swiftNestedFunctionUnsupported,
    .conditionalCompilationInSpan: .swiftConditionalCompilation,
    .anotherMarkerInsideSpan: .swiftMarkerInsideSpan,
    .multipleCandidateDeclarations: .swiftMultipleCandidates,
  ]

  private static let signatureCodes: [SignatureFailureCode: PublicErrorCode] = [
    .signatureMissing: .signatureMissing,
    .signatureAlgorithmUnsupported: .signatureAlgorithmUnsupported,
    .unknownKeyIdentifier: .signatureUnknownKeyIdentifier,
    .badSignature: .signatureBad,
  ]
}

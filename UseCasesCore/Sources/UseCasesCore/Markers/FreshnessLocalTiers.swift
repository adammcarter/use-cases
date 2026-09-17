/// The keyless local tier (freshness.ts `deriveLocalStatus` and the variant
/// family roll-up). Never influences the signed status.
enum FreshnessLocalTiers {
  /// One bound row's local status from its unsigned results.
  static func derive(
    _ allResults: [LocalVerificationResult],
    currentContextHash: String?,
    bindingSetHash: String,
  ) -> (status: LocalStatus, reason: String?) {
    guard !allResults.isEmpty else {
      return (.unverifiedLocal, nil)
    }
    // Attestation is a filter, not a verdict: a forged line beside an honest
    // one must not poison the honest one.
    let results = allResults.filter { result in
      result.attested != false
    }
    guard !results.isEmpty else {
      return (
        .unattestedLocal,
        "a verification result exists for this row but carries no valid run attestation, "
          + "so nothing proves a verifier was ever run for it here; "
          + "run `uc verify` to record a real one",
      )
    }
    let contextMatches = { (result: LocalVerificationResult) in
      currentContextHash.map { current in
        JavaScriptString.identical(result.contextHash, current)
      } ?? true
    }
    let bindingMatches = { (result: LocalVerificationResult) in
      JavaScriptString.identical(result.bindingSetHash, bindingSetHash)
    }
    if results.contains(where: { result in
      result.passed && bindingMatches(result) && contextMatches(result)
    }) {
      return (.verifiedLocal, nil)
    }
    let reason = if results.contains(where: { result in
      result.passed && !contextMatches(result)
    }) {
      "the verifier or its declared inputs changed since the last local run; re-run `uc verify`"
    } else if results.contains(where: { result in
      result.passed && !bindingMatches(result)
    }) {
      "the bound code span changed since the last local run; re-run `uc verify`"
    } else if results.contains(where: { result in
      !result.passed
    }) {
      "the last local verification did not pass; fix the row and re-run `uc verify`"
    } else {
      "the last local verification no longer matches the current row; re-run `uc verify`"
    }
    return (.staleLocal, reason)
  }

  /// A variant family's tier from its variants' results, recorded under
  /// `<family>::<key>`. VERIFIED_LOCAL only when every variant is; otherwise
  /// UNATTESTED over STALE over UNVERIFIED.
  static func family(
    rowIdentifier: String,
    keys: [String],
    members: [BindingSetMember],
    resultsByRow: OrderedStringMap<[LocalVerificationResult]>,
    currentContextHash: String?,
  ) throws(CodeUnitCanonicalJSONError)
    -> (tier: FreshnessLocalTier, breakdown: [VariantLocalStatus])
  {
    var breakdown: [VariantLocalStatus] = []
    for key in keys {
      let variantRowIdentifier = "\(rowIdentifier)::\(key)"
      let derived = try derive(
        resultsByRow[variantRowIdentifier] ?? [],
        currentContextHash: currentContextHash,
        bindingSetHash: BindingSetHash.compute(
          rowIdentifier: variantRowIdentifier,
          bindings: members,
        ),
      )
      breakdown.append(VariantLocalStatus(key: key, status: derived.status))
    }
    let statuses = breakdown.map(\.status)
    let allVerified = statuses.allSatisfy { status in
      status == .verifiedLocal
    }
    let status: LocalStatus = if allVerified {
      .verifiedLocal
    } else if statuses.contains(.unattestedLocal) {
      .unattestedLocal
    } else if statuses.contains(.staleLocal) {
      .staleLocal
    } else {
      .unverifiedLocal
    }
    let failing = breakdown.filter { entry in
      entry.status != .verifiedLocal
    }
    let reason = allVerified
      ? nil
      : "variant(s) not VERIFIED_LOCAL: \(failing.map(\.key).joined(separator: ", "))"
    return (FreshnessLocalTier(status: status, reason: reason), breakdown)
  }
}

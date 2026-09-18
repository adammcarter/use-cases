/// One row's freshness, derived IN THE SPEC'S ORDER (7.1 INVALID, 7.2 UNBOUND,
/// 7.3 SUSPECT removed, 7.4 UNPROVEN, 7.5 FRESH, 7.6 SUSPECT stale), then gated.
struct FreshnessRowDerivation {
  let row: FreshnessRow
  let integrity: [JSONObject]

  init(
    rowIdentifier: String,
    index: FreshnessIndex,
    input: FreshnessInput,
  ) throws(CodeUnitCanonicalJSONError) {
    let facts = try RowFacts(rowIdentifier: rowIdentifier, index: index)
    let integrity = facts.integrityErrors(index: index)
    var decision = facts.decide(integrity: integrity, contextHashes: index.contextHashes)

    let required = facts.inputRow?.requiredForRelease ?? false
    let policyBlock = Self.gate(
      &decision,
      rowIdentifier: rowIdentifier,
      required: required,
      input: input,
    )
    let bound = decision.status != .invalid
      && decision.status != .unbound
      && !facts.currentRegistered.isEmpty
    let local = try input.localResults.map { _ throws(CodeUnitCanonicalJSONError) in
      try facts.localTier(status: decision.status, bound: bound, index: index)
    }

    row = FreshnessRow(
      rowIdentifier: rowIdentifier,
      hashes: facts.hashes,
      status: decision.status,
      policyBlock: policyBlock,
      reasons: decision.reasons,
      knownBindingSlugs: facts.reconciliation?.registeredBindingSlugs ?? [],
      currentBindingSlugs: facts.reconciliation?.currentBindingSlugs ?? [],
      missingRegisteredBindingSlugs: facts.reconciliation?.missingRegisteredBindingSlugs ?? [],
      unregisteredCurrentBindingSlugs: facts.reconciliation?.unregisteredCurrentBindingSlugs ?? [],
      currentBindings: facts.currentRegistered,
      matchingProofEvent: decision.matching,
      latestTrustedProofEvent: facts.proofs.first,
      requiredAction: Self.requiredAction(decision.status, rowIdentifier: rowIdentifier),
      requiredForRelease: required,
      localTier: local?.tier,
      performedRun: input.performedRuns.map { _ in
        bound && index.performedRunRows.contains(rowIdentifier)
      },
      variantLocalStatus: local?.breakdown,
      currentBindingSetHash: facts.currentRegistered.isEmpty ? nil : facts.bindingSetHash,
    )
    self.integrity = integrity
  }

  /// The release-gate authority requirement, then the policy gate. An active
  /// requirement the matching proof's authority falls short of adds an
  /// AUTHORITY_INSUFFICIENT reason to an otherwise-unblocked FRESH required row.
  private static func gate(
    _ decision: inout StatusDecision,
    rowIdentifier: String,
    required: Bool,
    input: FreshnessInput,
  ) -> Bool {
    let authority = decision.matching?.value["authority"]
    let authorityInsufficient = input.policyMode == .release
      && required
      && decision.status == .fresh
      && FreshnessPolicy.authorityGateActive(input.releaseGate)
      && !FreshnessPolicy.authoritySatisfies(input.releaseGate, authority)
    if authorityInsufficient {
      decision.reasons.append(FreshnessStaleReasons.reason(
        "AUTHORITY_INSUFFICIENT",
        message: FreshnessPolicy.authorityReason(input.releaseGate, authority),
      ))
    }
    return FreshnessPolicy.isBlocked(
      mode: input.policyMode,
      context: PolicyDecisionContext(
        rowIdentifier: rowIdentifier,
        status: decision.status,
        requiredForRelease: required,
        isInvalid: decision.status == .invalid,
      ),
      customPolicy: input.customPolicy,
      authorityInsufficient: authorityInsufficient,
    )
  }

  private static func requiredAction(
    _ status: RowStatus,
    rowIdentifier: String,
  ) -> String? {
    switch status {
    case .suspect, .unproven:
      "use-cases prove --row \(rowIdentifier)"
    case .invalid:
      "use-cases scan (resolve binding integrity errors)"
    case .unbound:
      "use-cases bind --row \(rowIdentifier) --file <file> --mode <explicit|swift-func>"
    case .fresh:
      nil
    }
  }
}

/// The status, its reasons, and the proof that made the row FRESH.
private struct StatusDecision {
  var status: RowStatus
  var reasons: [JSONObject] = []
  var matching: FreshnessProofEvent?
}

/// What is known about one row before its status is decided.
private struct RowFacts {
  let rowIdentifier: String
  let inputRow: FreshnessInputRow?
  let reconciliation: RowReconciliation?
  /// C(row): the current, REGISTERED binding records.
  let currentRegistered: [CurrentBindingRecord]
  let hashes: FreshnessRowHashes?
  let bindingSetHash: String
  /// Newest first.
  let proofs: [FreshnessProofEvent]

  init(
    rowIdentifier: String,
    index: FreshnessIndex,
  ) throws(CodeUnitCanonicalJSONError) {
    self.rowIdentifier = rowIdentifier
    inputRow = index.rowById[rowIdentifier]
    reconciliation = index.reconciliationByRow[rowIdentifier]
    let known = OrderedStringSet(reconciliation?.registeredBindingSlugs ?? [])
    currentRegistered = (index.bindingsByRow[rowIdentifier] ?? []).filter { binding in
      known.contains(binding.bindingSlug)
    }
    hashes = try inputRow.map { row throws(CodeUnitCanonicalJSONError) in
      try FreshnessRowHashes(
        rowHash: RowHash.compute(.object(row.fields)),
        verificationPolicyHash: PolicyHash.verificationPolicyHash(row.verificationPolicy),
        approvalPolicyHash: PolicyHash.approvalPolicyHash(row.approvalPolicy),
      )
    }
    bindingSetHash = try BindingSetHash.compute(
      rowIdentifier: rowIdentifier,
      bindings: currentRegistered.map(\.setMember),
    )
    proofs = index.evidenceByRow[rowIdentifier] ?? []
  }

  func decide(
    integrity: [JSONObject],
    contextHashes: OrderedStringMap<String>?,
  ) -> StatusDecision {
    if !integrity.isEmpty {
      return StatusDecision(status: .invalid, reasons: integrity.map(Self.invalidReason))
    }
    let known = reconciliation?.registeredBindingSlugs ?? []
    if known.isEmpty, currentRegistered.isEmpty {
      return StatusDecision(status: .unbound)
    }
    let missing = reconciliation?.missingRegisteredBindingSlugs ?? []
    if !missing.isEmpty {
      var reasons = missing.map { slug in
        JSONObject([("code", .string("BINDING_REMOVED")), ("binding_slug", .string(slug))])
      }
      if currentRegistered.isEmpty {
        reasons.append(FreshnessStaleReasons.reason("ALL_BINDINGS_REMOVED"))
      }
      return StatusDecision(status: .suspect, reasons: reasons)
    }
    if !currentRegistered.isEmpty, proofs.isEmpty {
      return StatusDecision(status: .unproven)
    }
    let currentContextHash = contextHashes?[rowIdentifier]
    if let matching = proofs.first(where: { proof in
      matches(proof, contextHashes: contextHashes, currentContextHash: currentContextHash)
    }) {
      return StatusDecision(status: .fresh, matching: matching)
    }
    let stale = FreshnessStaleReasons(
      latest: proofs.first,
      hashes: hashes,
      bindingSetHash: bindingSetHash,
      current: currentRegistered,
      currentContextHash: contextHashes.map { _ in
        currentContextHash ?? ""
      },
    )
    return StatusDecision(status: .suspect, reasons: stale.derive())
  }

  /// Spec 7.5: the proof certifies the current row, policies and binding set,
  /// under a supported canon, against the current verification context when
  /// one is supplied, and the approval policy accepts it.
  private func matches(
    _ proof: FreshnessProofEvent,
    contextHashes: OrderedStringMap<String>?,
    currentContextHash: String?,
  ) -> Bool {
    guard let hashes else {
      return false
    }
    let itemsSupported = proof.items.allSatisfy { item in
      JavaScriptValue.strictlyEquals(
        item["span_canon_id"],
        MarkerConstants.spanCanonicalizerIdentifier,
      )
    }
    let contextMatches = contextHashes == nil
      || JavaScriptValue.strictlyEquals(proof.verification("context_hash"), currentContextHash)
    return JavaScriptValue.strictlyEquals(proof.row("row_hash"), hashes.rowHash)
      && JavaScriptValue.strictlyEquals(
        proof.row("verification_policy_hash"),
        hashes.verificationPolicyHash,
      )
      && JavaScriptValue.strictlyEquals(
        proof.row("approval_policy_hash"),
        hashes.approvalPolicyHash,
      )
      && JavaScriptValue.strictlyEquals(proof.bindingSetHash, bindingSetHash)
      && itemsSupported
      && contextMatches
      && approvalAccepts(proof)
  }

  /// Spec 7.5: a passing result, from the trusted producer when one is named.
  private func approvalAccepts(_ proof: FreshnessProofEvent) -> Bool {
    guard JavaScriptValue.strictlyEquals(proof.verification("result"), EvidenceLedger.passResult)
    else {
      return false
    }
    guard let expected = inputRow?.approvalPolicy["trusted_producer"]?.stringValue else {
      return true
    }
    return JavaScriptValue.strictlyEquals(proof.value["producer"]?["kind"], expected)
  }

  private static func invalidReason(_ error: JSONObject) -> JSONObject {
    var reason = JSONObject()
    reason["code"] = error["code"]
    if JavaScriptValue.isTruthy(error["binding_slug"]) {
      reason["binding_slug"] = error["binding_slug"]
    }
    if JavaScriptValue.isTruthy(error["message"]) {
      reason["message"] = error["message"]
    }
    return reason
  }
}

extension RowFacts {
  /// Spec 7.1: the row's scan errors, its unregistered markers, and — when the
  /// matrix does not know it — ROW_NOT_FOUND, each with its cure.
  func integrityErrors(index: FreshnessIndex) -> [JSONObject] {
    var errors: [JSONObject] = []
    for error in index.scanErrorsByRow[rowIdentifier] ?? [] {
      var object = JSONObject([
        ("code", .string(error.code.rawValue)),
        ("row_id", .string(rowIdentifier)),
      ])
      object["binding_slug"] = error.slug.map(JSONValue.string)
      object["file_path"] = .string(error.filePath)
      object["line"] = .number(Double(error.line))
      object["message"] = .string(error.message)
      errors.append(object)
    }
    let unregistered = index.unregisteredByRow[rowIdentifier] ?? []
    for detection in unregistered {
      errors.append(JSONObject([
        ("code", .string("UNREGISTERED_BINDING")),
        ("row_id", .string(rowIdentifier)),
        ("binding_slug", .string(detection.bindingSlug)),
        ("file_path", .string(detection.filePath)),
        ("line", .number(Double(detection.startLine))),
        (
          "message",
          .string(
            "current marker \(detection.bindingSlug) is not registered in the binding registry",
          ),
        ),
        ("remediation", .string(unregisteredRemediation(detection, index.renamedFrom))),
      ]))
    }
    if inputRow == nil {
      let previous = unregistered
        .first { detection in
          index.renamedFrom[detection.bindingSlug] != nil
        }
        .flatMap { detection in
          index.renamedFrom[detection.bindingSlug]
        }
      errors.append(JSONObject([
        ("code", .string("ROW_NOT_FOUND")),
        ("row_id", .string(rowIdentifier)),
        (
          "message",
          .string("row \(rowIdentifier) is bound or registered but is not a known use-case row")
        ),
        ("remediation", .string(rowNotFoundRemediation(previous))),
      ]))
    }
    return errors
  }

  private func unregisteredRemediation(
    _ detection: UnregisteredDetection,
    _ renamedFrom: OrderedStringMap<String>,
  ) -> String {
    let file = detection.filePath
    guard let previous = renamedFrom[detection.bindingSlug], !previous.isEmpty else {
      return "register the marker already in the source with "
        + "`use-cases bind --row \(rowIdentifier) --file \(file) --register-existing`"
        + ", or delete the marker if it is not wanted"
    }
    return "looks like \(rowIdentifier) was renamed from \(previous). Release the old registration "
      + "first — bind fails closed while it stands — with "
      + "`use-cases unbind --row \(previous) --reason row_renamed`, then run "
      + "`use-cases bind --row \(rowIdentifier) --file \(file) --register-existing`"
  }

  private func rowNotFoundRemediation(_ previous: String?) -> String {
    guard let previous, !previous.isEmpty else {
      return "add the row to the matrix, or — if the row id was RENAMED — update the "
        + "`@use-case:` marker(s) in source to the new id and re-register with "
        + "`use-cases bind --row <new-id> --file <file> --register-existing`"
    }
    return "looks like \(previous) was renamed to \(rowIdentifier) — add the renamed row to the "
      + "matrix (or rename it back), release the old registration with "
      + "`use-cases unbind --row \(previous) --reason row_renamed`, then re-register with "
      + "`use-cases bind --row \(rowIdentifier) --file <file> --register-existing`"
  }

  /// The keyless tier and, for a variant family, its breakdown. Emitted only
  /// when the caller supplied local results.
  func localTier(
    status: RowStatus,
    bound: Bool,
    index: FreshnessIndex,
  ) throws(CodeUnitCanonicalJSONError)
    -> (tier: FreshnessLocalTier, breakdown: [VariantLocalStatus]?)
  {
    let keys = inputRow?.familyVariantKeys ?? []
    let contextHash = index.contextHashes?[rowIdentifier]
    if bound, !keys.isEmpty, status != .fresh {
      let family = try FreshnessLocalTiers.family(
        rowIdentifier: rowIdentifier,
        keys: keys,
        members: currentRegistered.map(\.setMember),
        resultsByRow: index.localResultsByRow,
        currentContextHash: contextHash,
      )
      return (family.tier, family.breakdown)
    }
    if bound, status == .fresh {
      // A trusted signed proof is strictly stronger than an unsigned local run.
      return (
        FreshnessLocalTier(status: .verifiedLocal, reason: "backed by trusted signed proof"),
        nil,
      )
    }
    if bound {
      let derived = FreshnessLocalTiers.derive(
        index.localResultsByRow[rowIdentifier] ?? [],
        currentContextHash: contextHash,
        bindingSetHash: bindingSetHash,
      )
      return (FreshnessLocalTier(status: derived.status, reason: derived.reason), nil)
    }
    return (FreshnessLocalTier(status: nil, reason: nil), nil)
  }
}

extension CurrentBindingRecord {
  /// The seven members the binding-set hash takes.
  var setMember: BindingSetMember {
    BindingSetMember(
      bindingSlug: bindingSlug,
      rowIdentifier: rowIdentifier,
      filePath: filePath,
      extentKind: extentKind.rawValue,
      recognizerIdentifier: recognizerIdentifier,
      spanCanonicalizerIdentifier: spanCanonicalizerIdentifier,
      spanSHA256: span.sha256,
    )
  }
}

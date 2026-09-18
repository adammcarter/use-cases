/// The proof decision for one row of a prove run (`proveOneRow`).
struct ProveRowEvaluation {
  let options: ProveCommandOptions
  let prepared: ScanPreparation
  let contextRoot: String
  /// The key to sign with when this run appends; nil for a run that only
  /// reports candidates (untrusted, or a dry run).
  let appendKey: ProveSigningKey?
  let allowUnsafe: Bool
  /// True for an `--all` sweep, false for an explicit row.
  let sweep: Bool

  func prove(
    _ rowIdentifier: String,
    files: some MarkerFileSystem,
  ) throws(MarkerCommandError) -> ProveRowResult {
    guard let target = TargetRow(rowIdentifier, in: prepared) else {
      return ProveRowResult(
        rowIdentifier,
        .failed,
        reason: "ROW_NOT_FOUND",
        message: "row \(rowIdentifier) is not a known use-case row",
      )
    }
    // The signed tier has no variant model; an explicit row asked for the
    // unsupported thing, a sweep proves what it can.
    guard MarkerCommandInputs.rowVariants(target.loaded).isEmpty else {
      return ProveRowResult(
        rowIdentifier,
        sweep ? .skippedVariantFamily : .failed,
        reason: "VARIANT_FAMILY_UNSUPPORTED",
        message: "row \(rowIdentifier) is a variant family; signed proofs for variant families are "
          + "not supported yet — use the keyless loop "
          + "(`use-cases verify --row \(rowIdentifier)` then "
          + "`use-cases scan`) for per-variant local acceptance",
      )
    }
    switch target.status.status {
    case .unbound:
      return ProveRowResult(rowIdentifier, .skippedUnbound, message: "no binding; nothing to prove")
    case .invalid:
      return ProveRowResult(
        rowIdentifier,
        .failed,
        reason: "ROW_INVALID",
        message: "row \(rowIdentifier) has binding integrity errors; cannot prove",
      )
    case .fresh, .suspect, .unproven:
      return try proveBound(target, files: files)
    }
  }

  private func proveBound(
    _ target: TargetRow,
    files: some MarkerFileSystem,
  ) throws(MarkerCommandError) -> ProveRowResult {
    let row = try RecomputedRow(
      target,
      prepared: prepared,
      context: options.context,
      contextRoot: contextRoot,
      files: files,
    )
    let identifier = row.rowIdentifier
    if target.status.status == .fresh, !options.refresh {
      return ProveRowResult(identifier, .skippedFresh, message: "already FRESH", hashes: row.hashes)
    }
    let verification: ProofVerification
    switch try accept(row) {
    case let .refused(reason, message):
      return ProveRowResult(
        identifier,
        .failed,
        reason: reason,
        message: message,
        hashes: row.hashes,
      )
    case let .accepted(accepted):
      verification = accepted
    }
    return try append(row, verification: verification, files: files)
  }

  /// Accepted: a candidate when this run does not append, otherwise a signed
  /// proof on the ledger.
  private func append(
    _ row: RecomputedRow,
    verification: ProofVerification,
    files: some MarkerFileSystem,
  ) throws(MarkerCommandError) -> ProveRowResult {
    guard let appendKey else {
      return ProveRowResult(
        row.rowIdentifier,
        .candidate,
        message: "verification accepted; not appended",
        hashes: row.hashes,
      )
    }
    let contents = ProofEventContents(
      eventIdentifier: options.identifierFactory(),
      createdAt: options.generatedAt,
      row: row,
      verification: verification,
      producer: options.producer,
      authority: options.authority,
    )
    try ProofEventAppend.append(
      contents,
      evidencePath: options.evidencePath,
      signingKey: appendKey,
      files: files,
    )
    return ProveRowResult(
      row.rowIdentifier,
      .signed,
      proofEventAppended: true,
      eventIdentifier: contents.eventIdentifier,
      hashes: row.hashes,
    )
  }

  private enum Acceptance {
    case accepted(ProofVerification)
    case refused(reason: String, message: String)
  }

  /// The unsafe seam when the environment allows it; otherwise the row's
  /// latest result, which must have passed with prove's own hashes.
  private func accept(_ row: RecomputedRow) throws(MarkerCommandError) -> Acceptance {
    let rowIdentifier = row.rowIdentifier
    if options.unsafeAssumeVerificationPassed, allowUnsafe {
      return .accepted(ProofVerification(
        commandIdentifier: .string("acceptance.\(rowIdentifier)"),
        startedAt: .string(options.generatedAt),
      ))
    }
    guard let record = try ResultRecordReading
      .latest(rowIdentifier, in: options.verificationResults)
    else {
      return .refused(
        reason: "NO_PASSING_RESULT",
        message: "no verification result for row \(rowIdentifier); "
          + "run `use-cases verify --row \(rowIdentifier) --out <path>` first",
      )
    }
    if JavaScriptValue.strictlyEquals(record["status"], "blocked") {
      return .refused(
        reason: "RESULT_BLOCKED",
        message: "verification for \(rowIdentifier) is blocked (verifier could not be resolved)",
      )
    }
    guard JavaScriptValue.strictlyEquals(record["status"], "pass") else {
      return .refused(
        reason: "RESULT_FAILED",
        message: "verification for \(rowIdentifier) did not pass",
      )
    }
    let mismatches = try ResultRecordReading.mismatches(record, row: row)
    guard mismatches.isEmpty else {
      return .refused(
        reason: "HASH_MISMATCH",
        message: "verification result for \(rowIdentifier) is stale; recomputed hashes differ "
          + "(\(mismatches.joined(separator: ", ")))",
      )
    }
    let verifierIdentifier = record["verifier_id"].flatMap { value in
      value == .null ? nil : value
    }
    return .accepted(ProofVerification(
      commandIdentifier: verifierIdentifier ?? .string("acceptance.\(rowIdentifier)"),
      startedAt: record["created_at"],
    ))
  }
}

/// A consumed result read as the TypeScript reads an unchecked cast.
enum ResultRecordReading {
  /// The last record whose `row_id` is exactly `rowIdentifier`. A `null` line
  /// throws the TypeError V8 raises reading a member of it.
  static func latest(
    _ rowIdentifier: String,
    in records: [JSONValue]?,
  ) throws(MarkerCommandError) -> JSONValue? {
    var latest: JSONValue?
    for record in records ?? [] {
      guard record != .null else {
        throw .verificationResultUnreadable(
          message: "Cannot read properties of null (reading 'row_id')",
        )
      }
      if JavaScriptValue.strictlyEquals(record["row_id"], rowIdentifier) {
        latest = record
      }
    }
    return latest
  }

  /// The names of the hashes the record carries that differ from prove's own,
  /// in the order they are checked.
  static func mismatches(
    _ record: JSONValue,
    row: RecomputedRow,
  ) throws(MarkerCommandError) -> [String] {
    var mismatches: [String] = []
    if !JavaScriptValue.strictlyEquals(record["row_hash"], row.rowHash) {
      mismatches.append("row_hash")
    }
    if !JavaScriptValue.strictlyEquals(record["binding_set_hash"], row.bindingSetHash) {
      mismatches.append("binding_set_hash")
    }
    if try !stringArraysEqual(record["span_sha256s"], row.inputs.spanHashes) {
      mismatches.append("span_sha256s")
    }
    if !JavaScriptValue
      .strictlyEquals(record["verification_context_hash"], row.inputs.contextHash)
    {
      mismatches.append("verification_context_hash")
    }
    return mismatches
  }

  /// `stringArraysEqual(left, right)` over whatever `left` is: its `length`
  /// compared first, then `left.every(...)`, which only an array has.
  static func stringArraysEqual(
    _ left: JSONValue?,
    _ right: [String],
  ) throws(MarkerCommandError) -> Bool {
    let every = MarkerCommandError
      .verificationResultUnreadable(message: "left.every is not a function")
    switch left {
    case .none:
      throw .verificationResultUnreadable(
        message: "Cannot read properties of undefined (reading 'length')",
      )
    case .null:
      throw .verificationResultUnreadable(
        message: "Cannot read properties of null (reading 'length')",
      )
    case .bool, .number:
      return false
    case let .string(text):
      guard text.utf16.count == right.count else {
        return false
      }
      throw every
    case let .object(object):
      guard object["length"] == .number(Double(right.count)) else {
        return false
      }
      throw every
    case let .array(items):
      return items.count == right.count && zip(items, right).allSatisfy { item, expected in
        JavaScriptValue.strictlyEquals(item, expected)
      }
    }
  }
}

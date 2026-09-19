/// The outcome of validating one proof event.
public struct ProofEventValidation: Equatable, Sendable {
  public let isValid: Bool
  public let errors: [EvidenceError]
  /// The event, only when every check passed.
  public let event: JSONValue?
}

public struct EvidenceLedgerSummary: Equatable, Sendable {
  public let proofEventsChecked: Int
  public let proofEventsValid: Int
  public let proofEventsInvalid: Int
  public let appendOnly: Bool
  /// Counts per code, in the order each code first occurred.
  public let errorsByCode: [(code: String, count: Int)]

  public static func == (
    left: EvidenceLedgerSummary,
    right: EvidenceLedgerSummary,
  ) -> Bool {
    left.jsonValue == right.jsonValue
  }

  var jsonValue: JSONValue {
    .object(JSONObject([
      ("proof_events_checked", .number(Double(proofEventsChecked))),
      ("proof_events_valid", .number(Double(proofEventsValid))),
      ("proof_events_invalid", .number(Double(proofEventsInvalid))),
      ("append_only", .bool(appendOnly)),
      (
        "errors_by_code",
        .object(JSONObject(errorsByCode.map { entry in
          (entry.code, .number(Double(entry.count)))
        }))
      ),
    ]))
  }
}

public struct EvidenceLedgerValidation: Equatable, Sendable {
  public let isValid: Bool
  public let errors: [EvidenceError]
  /// Events that passed every per-event rule, in order.
  public let events: [JSONValue]
  public let appendOnly: Bool
  public let summary: EvidenceLedgerSummary
}

public extension EvidenceLedger {
  /// Every per-event rule, in the TypeScript's order: schema, signature,
  /// producer, verification result, then — over a schema-valid event only —
  /// the internal binding-set hash and the optional row existence.
  static func validateEvent(
    _ value: JSONValue,
    line: Int?,
    publicKeyResolver: PublicKeyResolver,
    yamlRowIdentifiers: Set<String>? = nil,
  ) throws(EvidenceLedgerError) -> ProofEventValidation {
    try validateEvent(
      value,
      line: line,
      publicKeyResolver: publicKeyResolver,
      knownRows: CodeUnitKey.set(yamlRowIdentifiers),
    )
  }

  internal static func validateEvent(
    _ value: JSONValue,
    line: Int?,
    publicKeyResolver: PublicKeyResolver,
    knownRows: Set<CodeUnitKey>?,
  ) throws(EvidenceLedgerError) -> ProofEventValidation {
    var check = ProofEventCheck(value: value, line: line)
    let schema = MarkerSchemaValidation.validateProofEvent(value)
    if !schema.isValid {
      check.fail(.evidenceSchemaInvalid, "proof event failed schema: \(schema.joinedMessage)")
    }
    do throws(ProofSignatureError) {
      if case let .failed(code, message) = try ProofSignature.verify(
        value,
        resolver: publicKeyResolver,
      ) {
        check.fail(EvidenceErrorCode(code), message)
      }
    } catch {
      throw .proofSignature(error)
    }
    check.checkPolicy()
    if schema.isValid {
      check.checkBindingSetHash()
      if let knownRows {
        check.checkRowExists(in: knownRows)
      }
    }
    return ProofEventValidation(
      isValid: check.errors.isEmpty,
      errors: check.errors,
      event: check.errors.isEmpty ? value : nil,
    )
  }

  /// The whole ledger: parse, append-only discipline against the base-ref text
  /// when one is given, then every per-event rule.
  static func validate(
    text: String,
    publicKeyResolver: PublicKeyResolver,
    baseReferenceOldText: String? = nil,
    yamlRowIdentifiers: Set<String>? = nil,
  ) throws(EvidenceLedgerError) -> EvidenceLedgerValidation {
    let read = read(text)
    var errors = read.errors
    var events: [JSONValue] = []
    var appendOnly = true
    if let baseReferenceOldText,
       case let .violated(violation) = AppendOnly.check(
         oldLines: AppendOnly.splitJSONLines(baseReferenceOldText),
         newLines: AppendOnly.splitJSONLines(text),
       )
    {
      appendOnly = false
      errors.append(EvidenceError(
        code: .appendOnlyViolation,
        line: violation.index + 1,
        message: violation.message,
      ))
    }
    let knownRows = CodeUnitKey.set(yamlRowIdentifiers)
    for entry in read.lines {
      let result = try validateEvent(
        entry.value,
        line: entry.line,
        publicKeyResolver: publicKeyResolver,
        knownRows: knownRows,
      )
      if let event = result.event {
        events.append(event)
      } else {
        errors += result.errors
      }
    }
    return EvidenceLedgerValidation(
      isValid: errors.isEmpty,
      errors: errors,
      events: events,
      appendOnly: appendOnly,
      summary: summary(
        errors: errors,
        checked: read.lines.count,
        valid: events.count,
        appendOnly: appendOnly,
      ),
    )
  }

  /// Read the ledger's base-ref version through git, then validate against it.
  static func validateAgainstBaseReference(
    text: String,
    baseReference: String,
    path: String,
    publicKeyResolver: PublicKeyResolver,
    yamlRowIdentifiers: Set<String>? = nil,
    workingDirectory: String?,
    runner: some GitRunning = GitProcessRunner(),
  ) throws(EvidenceLedgerError) -> EvidenceLedgerValidation {
    let oldText: String
    do throws(GitError) {
      oldText = try AppendOnly.readBaseReferenceFile(
        baseReference: baseReference,
        path: path,
        workingDirectory: workingDirectory,
        runner: runner,
      )
    } catch {
      throw .git(error)
    }
    return try validate(
      text: text,
      publicKeyResolver: publicKeyResolver,
      baseReferenceOldText: oldText,
      yamlRowIdentifiers: yamlRowIdentifiers,
    )
  }

  private static func summary(
    errors: [EvidenceError],
    checked: Int,
    valid: Int,
    appendOnly: Bool,
  ) -> EvidenceLedgerSummary {
    var counts = OrderedStringMap<Int>()
    for error in errors {
      counts[error.code.rawValue] = (counts[error.code.rawValue] ?? 0) + 1
    }
    return EvidenceLedgerSummary(
      proofEventsChecked: checked,
      proofEventsValid: valid,
      proofEventsInvalid: checked - valid,
      appendOnly: appendOnly,
      errorsByCode: counts.pairs.map { pair in
        (code: pair.key, count: pair.value)
      },
    )
  }
}

/// The accumulating state of one event's checks.
private struct ProofEventCheck {
  let value: JSONValue
  let line: Int?
  let eventIdentifier: String?
  let rowIdentifier: String?
  var errors: [EvidenceError] = []

  init(
    value: JSONValue,
    line: Int?,
  ) {
    self.value = value
    self.line = line
    eventIdentifier = value["event_id"]?.stringValue
    rowIdentifier = value["row"]?["row_id"]?.stringValue
  }

  mutating func fail(
    _ code: EvidenceErrorCode,
    _ message: String,
    rowIdentifier overridden: String? = nil,
  ) {
    errors.append(EvidenceError(
      code: code,
      line: line,
      message: message,
      eventIdentifier: eventIdentifier,
      rowIdentifier: overridden ?? rowIdentifier,
    ))
  }

  /// A dedicated code only when the field is present but wrong; an absent one
  /// is the schema's to report.
  mutating func checkPolicy() {
    let producer = EvidenceLedger.trustedProducerKind
    if let kind = value["producer"]?["kind"], !isString(kind, producer) {
      let spelled = JavaScriptString.text(of: kind)
      fail(
        .producerNotTrusted,
        "producer.kind is \(spelled); only \(producer) may mint proof events",
      )
    }
    let pass = EvidenceLedger.passResult
    if let result = value["verification"]?["result"], !isString(result, pass) {
      let spelled = JavaScriptString.text(of: result)
      fail(
        .verificationNotPass,
        "verification.result is \(spelled); only \"\(pass)\" proofs may be appended",
      )
    }
  }

  /// The embedded hash must recompute from the items (spec 5.4): a mismatch is
  /// INVALID, distinct from SUSPECT drift.
  mutating func checkBindingSetHash() {
    guard let row = value["row"]?["row_id"]?.stringValue,
          let embedded = value["bindings"]?["binding_set_hash"]?.stringValue,
          let items = value["bindings"]?["items"]?.arrayValue
    else {
      return
    }
    let members = items.compactMap(BindingSetMember.init(json:))
    guard members.count == items.count,
          let recomputed = try? BindingSetHash.compute(rowIdentifier: row, bindings: members)
    else {
      return
    }
    if !JavaScriptString.identical(recomputed, embedded) {
      fail(
        .bindingSetHashMismatch,
        "binding_set_hash \(embedded) does not recompute from items (got \(recomputed))",
      )
    }
  }

  mutating func checkRowExists(in knownRows: Set<CodeUnitKey>) {
    guard let row = value["row"]?["row_id"]?.stringValue else {
      return
    }
    if !knownRows.contains(CodeUnitKey(row)) {
      fail(
        .evidenceRowMissing,
        "proof event row_id \(row) is not a known YAML row",
        rowIdentifier: row,
      )
    }
  }

  private func isString(
    _ value: JSONValue,
    _ expected: String,
  ) -> Bool {
    guard let text = value.stringValue else {
      return false
    }
    return JavaScriptString.identical(text, expected)
  }
}

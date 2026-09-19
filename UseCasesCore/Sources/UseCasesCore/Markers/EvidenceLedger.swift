/// Every way the evidence ledger can be invalid (spec 5.3 / 5.4 / 7.1).
/// Frozen wire codes; the signature codes match ``SignatureFailureCode``.
public enum EvidenceErrorCode: String, CaseIterable, Equatable, Sendable {
  case jsonParseError = "JSON_PARSE_ERROR"
  case evidenceSchemaInvalid = "EVIDENCE_SCHEMA_INVALID"
  case signatureMissing = "SIGNATURE_MISSING"
  case signatureAlgorithmUnsupported = "SIGNATURE_ALG_UNSUPPORTED"
  case unknownKeyIdentifier = "UNKNOWN_KEY_ID"
  case badSignature = "BAD_SIGNATURE"
  case producerNotTrusted = "PRODUCER_NOT_TRUSTED"
  case verificationNotPass = "VERIFICATION_NOT_PASS"
  case bindingSetHashMismatch = "BINDING_SET_HASH_MISMATCH"
  case evidenceRowMissing = "EVIDENCE_ROW_MISSING"
  case appendOnlyViolation = "APPEND_ONLY_VIOLATION"

  init(_ code: SignatureFailureCode) {
    switch code {
    case .signatureMissing: self = .signatureMissing
    case .signatureAlgorithmUnsupported: self = .signatureAlgorithmUnsupported
    case .unknownKeyIdentifier: self = .unknownKeyIdentifier
    case .badSignature: self = .badSignature
    }
  }
}

public struct EvidenceError: Equatable, Sendable {
  public let code: EvidenceErrorCode
  /// 1-based source line, or nil for a ledger-level error.
  public let line: Int?
  public let message: String
  public let eventIdentifier: String?
  public let rowIdentifier: String?

  public init(
    code: EvidenceErrorCode,
    line: Int?,
    message: String,
    eventIdentifier: String? = nil,
    rowIdentifier: String? = nil,
  ) {
    self.code = code
    self.line = line
    self.message = message
    self.eventIdentifier = eventIdentifier
    self.rowIdentifier = rowIdentifier
  }

  /// `{ code, line, message, event_id?, row_id? }`.
  var jsonValue: JSONValue {
    var object = JSONObject([
      ("code", .string(code.rawValue)),
      ("line", JSONValue.optionalNumber(line)),
      ("message", .string(message)),
    ])
    object["event_id"] = eventIdentifier.map(JSONValue.string)
    object["row_id"] = rowIdentifier.map(JSONValue.string)
    return .object(object)
  }
}

/// One parsed JSONL line; `value` is parsed but not yet validated.
public struct EvidenceLine: Equatable, Sendable {
  public let line: Int
  public let value: JSONValue
}

public struct ReadEvidenceResult: Equatable, Sendable {
  public let lines: [EvidenceLine]
  /// JSON_PARSE_ERROR entries only.
  public let errors: [EvidenceError]
}

/// What stops a ledger being validated at all — each is a throw in the
/// TypeScript, not a diagnostic.
public enum EvidenceLedgerError: Error, Equatable, Sendable {
  case proofSignature(ProofSignatureError)
  case git(GitError)

  public var code: String {
    switch self {
    case let .proofSignature(error): error.code
    case let .git(error): error.code
    }
  }

  public var message: String {
    switch self {
    case let .proofSignature(error): error.message
    case let .git(error): error.message
    }
  }
}

/// The signed evidence ledger (evidenceLedger.ts, spec section 5): pure text in,
/// validated proof events and precise error codes out. It deliberately does NOT
/// compare embedded span hashes with current code (spec 5.4): that drift is
/// SUSPECT and belongs to the freshness machine.
public enum EvidenceLedger {
  /// The only producer allowed to mint proof events (spec 5.3 rule 4).
  public static let trustedProducerKind = "trusted-ci-prover"
  /// The only verification result an appended proof may carry (rule 5).
  public static let passResult = "pass"

  /// One parsed value per non-blank line; a line that is not JSON is a
  /// JSON_PARSE_ERROR carrying its 1-based number, and reading continues.
  public static func read(_ text: String) -> ReadEvidenceResult {
    var lines: [EvidenceLine] = []
    var errors: [EvidenceError] = []
    for (index, raw) in JavaScriptString.split(text, on: CodeUnits.lineFeed).enumerated() {
      guard !JavaScriptString.trim(raw).isEmpty else {
        continue
      }
      let number = index + 1
      do throws(SchemaError) {
        try lines.append(EvidenceLine(line: number, value: JSONParser.parse(raw)))
      } catch {
        errors.append(EvidenceError(
          code: .jsonParseError,
          line: number,
          message: "line \(number) is not valid JSON: \(error.message)",
        ))
      }
    }
    return ReadEvidenceResult(lines: lines, errors: errors)
  }

  /// A pure missing-key failure: a signed proof with no key supplied to check
  /// it. Not corruption — the ordinary keyless path.
  public static func isKeyResolutionOnly(_ error: EvidenceError) -> Bool {
    error.code == .signatureMissing || error.code == .unknownKeyIdentifier
  }

  /// True when EVERY error is a pure missing-key failure (trivially true for
  /// none), so the keyless path can stay exit-0 while real corruption fails.
  public static func errorsAreKeyResolutionOnly(_ errors: [EvidenceError]) -> Bool {
    errors.allSatisfy(isKeyResolutionOnly)
  }
}

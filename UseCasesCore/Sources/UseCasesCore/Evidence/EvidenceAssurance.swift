/// `EvidenceAssuranceInput`. Replay feeds it values read from ledgers that
/// nothing validated, so each is the JSON it is; nil is `undefined`.
public struct EvidenceAssuranceInput: Sendable, Equatable {
  public let kind: JSONValue
  public let origin: JSONValue?
  public let captureMethod: JSONValue?
  public let executionMethod: JSONValue?
  public let exitStatus: Double?
  public let digestComputedByTool: Bool?

  public init(
    kind: JSONValue,
    origin: JSONValue?,
    captureMethod: JSONValue?,
    executionMethod: JSONValue? = nil,
    exitStatus: Double? = nil,
    digestComputedByTool: Bool? = nil,
  ) {
    self.kind = kind
    self.origin = origin
    self.captureMethod = captureMethod
    self.executionMethod = executionMethod
    self.exitStatus = exitStatus
    self.digestComputedByTool = digestComputedByTool
  }
}

/// A freshness policy's answer to a semantic hash that moved.
public enum EvidenceHashMismatchPolicy: String, CaseIterable, Sendable {
  case needsReview = "needs_review"
  case stale
}

public enum EvidenceFreshnessState: String, CaseIterable, Sendable {
  case current
  case needsReview = "needs_review"
  case stale
  case unknown
  case invalidated
}

public struct EvidenceFreshnessInput: Sendable, Equatable {
  public let explicitInvalidation: Bool?
  public let semanticHashMatches: Bool?
  /// `policy.semanticHashMismatch`; nil when there is no policy.
  public let semanticHashMismatchPolicy: EvidenceHashMismatchPolicy?

  public init(
    explicitInvalidation: Bool? = nil,
    semanticHashMatches: Bool? = nil,
    semanticHashMismatchPolicy: EvidenceHashMismatchPolicy? = nil,
  ) {
    self.explicitInvalidation = explicitInvalidation
    self.semanticHashMatches = semanticHashMatches
    self.semanticHashMismatchPolicy = semanticHashMismatchPolicy
  }
}

public struct EvidenceFreshnessResult: Sendable, Equatable {
  public let state: EvidenceFreshnessState
  public let basis: String

  /// `{ state, basis }`.
  public var jsonValue: JSONValue {
    .object(JSONObject([("state", .string(state.rawValue)), ("basis", .string(basis))]))
  }
}

/// packages/core/src/evidence/assurance.ts.
public enum EvidenceAssurance {
  /// `deriveEvidenceAssurance`: `{ origin, capture_method, execution_method,
  /// integrity, reproducibility, result, class }`, an `undefined` origin or
  /// capture method left out.
  public static func derive(_ input: EvidenceAssuranceInput) -> JSONObject {
    let kind = input.kind
    let derivedExecution = JavaScriptValue.strictlyEquals(kind, "test_result")
      ? "test"
      : JavaScriptValue.strictlyEquals(kind, "command_result") ? "command" : "none"
    let executionMethod = JavaScriptValue.coalesce(input.executionMethod, .string(derivedExecution))
    let isExecuted = JavaScriptValue.strictlyEquals(input.captureMethod, "executed")
      && (JavaScriptValue.strictlyEquals(executionMethod, "command")
        || JavaScriptValue.strictlyEquals(executionMethod, "test"))
    let assuranceClass = if JavaScriptValue.strictlyEquals(kind, "url") {
      "reference"
    } else if isExecuted {
      "reproducible"
    } else if JavaScriptValue.strictlyEquals(input.captureMethod, "observed") {
      "observed"
    } else {
      "reported"
    }

    var assurance = JSONObject()
    assurance["origin"] = input.origin
    assurance["capture_method"] = input.captureMethod
    assurance["execution_method"] = executionMethod
    assurance["integrity"] = .string(input
      .digestComputedByTool == true ? "tool_computed_digest" : "none")
    assurance["reproducibility"] =
      .string(assuranceClass == "reproducible" ? "structured_command" : "none")
    assurance["result"] = .string(input.exitStatus == nil || input
      .exitStatus == 0 ? "pass" : "fail")
    assurance["class"] = .string(assuranceClass)
    return assurance
  }

  /// `evaluateEvidenceFreshness`.
  public static func evaluateFreshness(_ input: EvidenceFreshnessInput) -> EvidenceFreshnessResult {
    if input.explicitInvalidation == true {
      return EvidenceFreshnessResult(state: .invalidated, basis: "explicit_invalidation")
    }
    guard let policy = input.semanticHashMismatchPolicy else {
      return EvidenceFreshnessResult(state: .unknown, basis: "missing_evaluation_context")
    }
    if input.semanticHashMatches == false {
      let state: EvidenceFreshnessState = policy == .stale ? .stale : .needsReview
      return EvidenceFreshnessResult(state: state, basis: "use_case_semantic_hash_mismatch")
    }
    return EvidenceFreshnessResult(state: .current, basis: "policy_match")
  }
}

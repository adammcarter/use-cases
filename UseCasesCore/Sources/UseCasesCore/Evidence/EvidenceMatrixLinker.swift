public enum EvidenceLinkResolution: String, CaseIterable, Sendable {
  case resolved
  case missing
  case ambiguous
  case unknownDueToMatrixIncomplete = "unknown_due_to_matrix_incomplete"
}

public enum EvidenceLinkSemanticHash: String, CaseIterable, Sendable {
  case match
  case mismatch
  case unknown
}

/// One evidence target resolved against the matrix (`EvidenceMatrixLink`).
public struct EvidenceMatrixLink: Sendable, Equatable {
  public let evidenceIdentifier: String
  /// The target's `use_case_id` as written — any JSON, nil when absent.
  public let useCaseIdentifier: JSONValue?
  /// The target's `scenario_id` as written — any JSON, nil when absent.
  public let scenarioIdentifier: JSONValue?
  public let resolution: EvidenceLinkResolution
  public let semanticHash: EvidenceLinkSemanticHash
  public let sourcePath: String?

  /// The TypeScript object as `JSON.stringify` spells it: camelCase members,
  /// an `undefined` id left out, a missing source path `null`.
  public var jsonValue: JSONValue {
    var object = JSONObject([("evidenceId", .string(evidenceIdentifier))])
    object["useCaseId"] = useCaseIdentifier
    object["scenarioId"] = scenarioIdentifier
    object["resolution"] = .string(resolution.rawValue)
    object["semanticHash"] = .string(semanticHash.rawValue)
    object["sourcePath"] = sourcePath.map(JSONValue.string) ?? .null
    return .object(object)
  }
}

/// packages/core/src/evidence/linkEvidence.ts.
public enum EvidenceMatrixLinker {
  //: @use-case:evidence.ledger.product_proof_map
  /// `linkEvidenceToMatrix`: every target of every aggregate, resolved, then
  /// sorted by `` `${evidenceId}:${useCaseId}` `` with `localeCompare`.
  public static func link(
    evidence: EvidenceSnapshot,
    matrix: MatrixSnapshot,
  ) -> [EvidenceMatrixLink] {
    var links: [EvidenceMatrixLink] = []
    for aggregate in evidence.aggregates {
      for target in aggregate.targetLinks {
        links.append(link(aggregate.evidenceIdentifier, target, matrix))
      }
    }
    return links.sorted { left, right in
      JavaScriptStringOrder.localeAscending(sortKey(left), sortKey(right))
    }
  }

  //: @use-case:end evidence.ledger.product_proof_map

  private static func link(
    _ evidenceIdentifier: String,
    _ target: JSONValue,
    _ matrix: MatrixSnapshot,
  ) -> EvidenceMatrixLink {
    let useCaseIdentifier = JavaScriptValue.member(target, "use_case_id")
    // `byId.get(id)` finds nothing for an id that is not a string.
    let resolution = useCaseIdentifier?.stringValue.map(matrix.resolveUseCase)
    func unresolved(_ kind: EvidenceLinkResolution) -> EvidenceMatrixLink {
      EvidenceMatrixLink(
        evidenceIdentifier: evidenceIdentifier,
        useCaseIdentifier: useCaseIdentifier,
        scenarioIdentifier: JavaScriptValue.member(target, "scenario_id"),
        resolution: kind,
        semanticHash: .unknown,
        sourcePath: nil,
      )
    }
    switch resolution {
    case nil, .missing:
      return unresolved(matrix.isComplete ? .missing : .unknownDueToMatrixIncomplete)
    case .ambiguous:
      return unresolved(.ambiguous)
    case let .resolved(_, useCase):
      let matches = JavaScriptValue.strictlyEquals(
        JavaScriptValue.member(target, "use_case_semantic_hash"),
        useCase.semanticHash,
      )
      return EvidenceMatrixLink(
        evidenceIdentifier: evidenceIdentifier,
        useCaseIdentifier: useCaseIdentifier,
        scenarioIdentifier: JavaScriptValue.member(target, "scenario_id"),
        resolution: .resolved,
        semanticHash: matches ? .match : .mismatch,
        sourcePath: useCase.source.path,
      )
    }
  }

  private static func sortKey(_ link: EvidenceMatrixLink) -> String {
    "\(link.evidenceIdentifier):\(JavaScriptString.text(of: link.useCaseIdentifier))"
  }
}

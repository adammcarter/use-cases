/// Hashes of a row's policy objects (policyHash.ts): canonical JSON with keys
/// in UTF-16 code-unit order, then sha256.
public enum PolicyHash {
  public static func compute(_ policy: JSONValue) throws(CodeUnitCanonicalJSONError) -> String {
    try CodeUnitCanonicalJSON.sha256(policy)
  }

  /// `verification_policy_hash`.
  public static func verificationPolicyHash(_ policy: JSONValue) throws(CodeUnitCanonicalJSONError)
    -> String
  {
    try compute(policy)
  }

  /// `approval_policy_hash`.
  public static func approvalPolicyHash(_ policy: JSONValue) throws(CodeUnitCanonicalJSONError)
    -> String
  {
    try compute(policy)
  }
}

/// A row's freshness hash (rowHash.ts). It REUSES the semantic hash — keys in
/// locale-collated order — so it stays consistent with the rest of the system.
/// It is the one marker hash that is not code-unit ordered.
public enum RowHash {
  public static func compute(_ row: JSONValue) -> String {
    SemanticHash.compute(row)
  }
}

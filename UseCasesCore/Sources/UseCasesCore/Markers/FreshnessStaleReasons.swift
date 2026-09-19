/// Spec 7.6: why the latest trusted proof no longer vouches for the row
/// (freshness.ts `deriveStaleReasons`). Each reason keeps the member order of
/// the TypeScript literal that builds it.
///
/// The TypeScript's two guards for a missing latest proof and missing row
/// hashes are kept, though the status cascade never reaches them: a row with no
/// proof is UNPROVEN and a row outside the matrix is INVALID first.
struct FreshnessStaleReasons {
  let latest: FreshnessProofEvent?
  let hashes: FreshnessRowHashes?
  let bindingSetHash: String
  let current: [CurrentBindingRecord]
  /// The recomputed context hash, or nil when the caller supplied no context
  /// hashes, in which case context drift is not checked.
  let currentContextHash: String?

  func derive() -> [JSONObject] {
    guard let latest else {
      return [Self.reason("NO_MATCHING_TRUSTED_PROOF")]
    }
    var reasons = policyReasons(latest)
    let bindingReasons = perBindingReasons(latest)
    reasons += bindingReasons
    if bindingReasons.isEmpty,
       !JavaScriptValue.strictlyEquals(latest.bindingSetHash, bindingSetHash)
    {
      reasons.append(Self.reason("BINDING_SET_CHANGED", message: drift(
        "binding set hash changed since proof",
        latest.bindingSetHash,
        bindingSetHash,
      )))
    }
    if reasons.isEmpty {
      reasons.append(Self.reason("NO_MATCHING_TRUSTED_PROOF"))
    }
    return reasons
  }

  private func policyReasons(_ latest: FreshnessProofEvent) -> [JSONObject] {
    var reasons: [JSONObject] = []
    if let currentContextHash,
       !JavaScriptValue.strictlyEquals(latest.verification("context_hash"), currentContextHash)
    {
      let previous = JavaScriptValue.text(latest.verification("context_hash"))
      reasons.append(Self.reason(
        "VERIFICATION_CONTEXT_CHANGED",
        message: "verification context changed since proof (\(previous) -> \(currentContextHash)); "
          + "the verifier or its declared inputs were modified",
      ))
    }
    let checks = [
      ("ROW_HASH_CHANGED", "row_hash", "row hash", hashes?.rowHash ?? ""),
      (
        "VERIFICATION_POLICY_CHANGED",
        "verification_policy_hash",
        "verification policy",
        hashes?.verificationPolicyHash ?? "",
      ),
      (
        "APPROVAL_POLICY_CHANGED",
        "approval_policy_hash",
        "approval policy",
        hashes?.approvalPolicyHash ?? "",
      ),
    ]
    for (code, key, label, current) in checks
      where !JavaScriptValue.strictlyEquals(latest.row(key), current)
    {
      reasons.append(Self.reason(code, message: drift(
        "\(label) changed since proof",
        latest.row(key),
        current,
      )))
    }
    return reasons
  }

  private func perBindingReasons(_ latest: FreshnessProofEvent) -> [JSONObject] {
    var proofItems = OrderedStringMap<JSONObject>()
    for item in latest.items {
      proofItems[item["binding_slug"]?.stringValue ?? ""] = item
    }
    var currentSlugs = OrderedStringSet()
    for binding in current {
      currentSlugs.insert(binding.bindingSlug)
    }
    var reasons: [JSONObject] = []
    for binding in current {
      guard let item = proofItems[binding.bindingSlug] else {
        reasons.append(JSONObject([
          ("code", .string("BINDING_ADDED")),
          ("binding_slug", .string(binding.bindingSlug)),
        ]))
        continue
      }
      reasons += Self.itemReasons(item, binding)
    }
    for item in latest.items {
      let slug = item["binding_slug"]?.stringValue ?? ""
      if !currentSlugs.contains(slug) {
        reasons.append(JSONObject([
          ("code", .string("BINDING_REMOVED")),
          ("binding_slug", .string(slug)),
        ]))
      }
    }
    return reasons
  }

  private static func itemReasons(
    _ item: JSONObject,
    _ binding: CurrentBindingRecord,
  ) -> [JSONObject] {
    var reasons: [JSONObject] = []
    if !JavaScriptValue.strictlyEquals(item["file_path"], binding.filePath) {
      var reason = JSONObject([
        ("code", .string("BINDING_PATH_CHANGED")),
        ("binding_slug", .string(binding.bindingSlug)),
      ])
      reason["expected_file_path"] = item["file_path"]
      reason["actual_file_path"] = .string(binding.filePath)
      reasons.append(reason)
    }
    if !JavaScriptValue.strictlyEquals(item["span_sha256"], binding.span.sha256) {
      var reason = JSONObject([
        ("code", .string("CODE_SPAN_CHANGED")),
        ("binding_slug", .string(binding.bindingSlug)),
      ])
      reason["expected_span_sha256"] = item["span_sha256"]
      reason["actual_span_sha256"] = .string(binding.span.sha256)
      reasons.append(reason)
    }
    if !JavaScriptValue.strictlyEquals(item["span_canon_id"], binding.spanCanonicalizerIdentifier) {
      let previous = JavaScriptValue.text(item["span_canon_id"])
      reasons.append(JSONObject([
        ("code", .string("CANON_CHANGED")),
        ("binding_slug", .string(binding.bindingSlug)),
        (
          "message",
          .string("span canon changed (\(previous) -> \(binding.spanCanonicalizerIdentifier))"),
        ),
      ]))
    }
    return reasons
  }

  private func drift(
    _ prefix: String,
    _ previous: JSONValue?,
    _ current: String,
  ) -> String {
    "\(prefix) (\(JavaScriptValue.text(previous)) -> \(current))"
  }

  static func reason(
    _ code: String,
    message: String? = nil,
  ) -> JSONObject {
    var reason = JSONObject([("code", .string(code))])
    reason["message"] = message.map(JSONValue.string)
    return reason
  }
}

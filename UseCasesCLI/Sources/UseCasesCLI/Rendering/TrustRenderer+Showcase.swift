import UseCasesCore

extension TrustRenderer {
  /// `renderShowcaseStatus`: the run's state and its approval.
  static func showcaseStatusLines(_ data: JSONValue) -> [String] {
    var lines = [
      "showcase \(JavaScriptReading.text(data["run_id"])): "
        + "\(JavaScriptReading.text(data["execution_status"])) \u{00B7} "
        + "\(JavaScriptReading.text(data["run_outcome"]))",
      "approval: \(JavaScriptReading.text(data["approval_state"]))",
    ]
    let approval = data["approval"]
    if JavaScriptReading.isTruthy(approval?["actor_type"]),
       JavaScriptReading.isTruthy(approval?["assurance_tier"])
    {
      lines.append(
        "approved by \(JavaScriptReading.text(approval?["actor_type"])) \u{00B7} "
          + "tier \(JavaScriptReading.text(approval?["assurance_tier"]))",
      )
    }
    return lines
  }

  /// `renderTrustObjectHuman`: an approval request, wherever it is rendered,
  /// reads as the request and how to sign it; any other value is nil.
  static func renderApprovalRequest(_ value: JSONValue) -> String? {
    guard value["approval_request_schema"] == .string("ucase-approval-request-v1"),
          let binding = value["binding"], case .object = binding
    else {
      return nil
    }
    let lines = [
      "approval request",
      "",
      "  run \(JavaScriptReading.text(binding["run_id"]))",
      "  finish event \(JavaScriptReading.text(binding["finish_event_id"]))",
      "  plan \(JavaScriptReading.text(binding["plan_content_hash"]))",
      "  nonce \(JavaScriptReading.text(value["jti"]))",
      "  expires \(JavaScriptReading.text(value["exp"]))",
      "",
      "Sign out-of-band:",
      "  uc approve-run --request <request-file> --key-file <out-of-scope-key> "
        + "--key-id <keyring-key-id> --json",
      "",
      EnvelopeRenderer.footer,
    ]
    return lines.joined(separator: "\n") + "\n"
  }
}

import UseCasesCore

extension TrustRenderer {
  /// `renderVerify`: the counts and a line per result, or — for a dry run,
  /// which has no results by design — the plan.
  static func verifyLines(_ data: JSONValue) -> [String] {
    if JavaScriptReading.isTruthy(data["dry_run"]) {
      return plannedLines(data["planned"]?.arrayValue ?? [])
    }
    let results = data["results"]?.arrayValue ?? []
    let statuses = results.map { result in
      result["status"]?.stringValue
    }
    var parts: [String] = []
    for (status, word) in [("pass", "passed"), ("fail", "failed"), ("blocked", "blocked")] {
      let count = statuses.filter { candidate in
        candidate == status
      }.count
      if count > 0 {
        parts.append("\(count) \(word)")
      }
    }
    let behaviourWord = results.count == 1 ? "behaviour" : "behaviours"
    var lines = [
      results.isEmpty
        ? "verify: no bound behaviours to verify"
        : "verify: \(results.count) \(behaviourWord) \u{2014} \(parts.joined(separator: ", "))",
      "",
    ]
    for result in results {
      let status = JavaScriptReading.text(result["status"])
      let glyph = status == "pass" ? "\u{2713}" : "\u{2717}"
      let rowIdentifier = JavaScriptReading.text(result["row_id"])
      let word = JavaScriptReading.padEnd(status.uppercased(), 7)
      lines.append("  \(glyph) \(word) \(rowIdentifier)")
      if status != "pass" {
        lines
          .append("      \u{2192} fix the row and re-run `use-cases verify --row \(rowIdentifier)`")
      }
    }
    return lines
  }

  private static func plannedLines(_ planned: [JSONValue]) -> [String] {
    let willRun = planned.filter { entry in
      entry["disposition"] == .string("run")
    }.count
    let behaviourWord = planned.count == 1 ? "behaviour" : "behaviours"
    var lines = [
      planned.isEmpty
        ? "verify --dry-run: no bound behaviours to verify"
        : "verify --dry-run: \(planned.count) \(behaviourWord) \u{2014} \(willRun) would run. "
        + "Nothing was executed; nothing was written.",
      "",
    ]
    for entry in planned {
      let rowIdentifier = JavaScriptReading.text(entry["row_id"])
      let verifier = entry["verifier_id"]
      if entry["disposition"] == .string("run") {
        let command = (entry["command"]?.arrayValue ?? []).map(JavaScriptReading.text)
        lines.append("  \u{00B7} \(rowIdentifier)")
        let verifierText = JavaScriptReading.text(verifier)
        lines.append("      would run [\(verifierText)]: \(command.joined(separator: " "))")
      } else {
        let disposition = JavaScriptReading.text(entry["disposition"])
        lines.append("  \u{2717} \(rowIdentifier) \u{2014} \(disposition.uppercased())")
        if disposition == "blocked" {
          let declared = JavaScriptReading.isTruthy(verifier)
            ? " (\(JavaScriptReading.text(verifier)) is not declared)"
            : ""
          lines.append("      no runnable verifier\(declared)")
        } else {
          lines.append("      resolve the binding integrity errors first (`use-cases scan`)")
        }
      }
    }
    lines.append("")
    lines.append("Re-run without --dry-run to actually verify.")
    return lines
  }
}

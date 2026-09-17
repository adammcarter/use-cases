import UseCasesCore

extension TrustRenderer {
  /// `renderScan`: the counts (the keyless local green counted apart from
  /// signed FRESH), the acceptance conclusion, a line per row, the integrity
  /// errors, and the gate.
  static func scanLines(_ data: JSONValue) -> [String] {
    let status = data["status"]
    let rows = status?["rows"]?.arrayValue ?? []
    let summary = JavaScriptReading.present(status?["summary"])
    let count = { (key: String) in
      summary == nil ? 0 : JavaScriptReading.number(summary?[key])
    }
    var lines: [String] = []

    let keylessGreen = rows.filter { row in
      row["status"] == .string("UNPROVEN") && row["local_status"] == .string("VERIFIED_LOCAL")
    }.count
    var parts: [String] = []
    let tallies: [(Double, String)] = [
      (count("fresh"), "fresh"),
      (Double(keylessGreen), "verified-local"),
      (count("suspect"), "suspect"),
      (count("unproven") - Double(keylessGreen), "unproven"),
      (count("unbound"), "unbound"),
      (count("invalid"), "invalid"),
    ]
    for (value, word) in tallies where value > 0 {
      parts.append("\(JavaScriptNumber.text(value)) \(word)")
    }
    let behaviourWord = rows.count == 1 ? "behaviour" : "behaviours"
    lines.append(parts.isEmpty
      ? "\(rows.count) \(behaviourWord)"
      : "\(rows.count) \(behaviourWord): \(parts.joined(separator: ", "))")

    // The acceptance conclusion, stated outright: a green guard is not a claim.
    if let claim = status?["acceptance_claim"], JavaScriptReading.isTruthy(claim) {
      let statement = JavaScriptReading.text(claim["statement"])
      lines.append(JavaScriptReading.isTruthy(claim["claimable"])
        ? "\u{2713} acceptance: \(statement)"
        : "\u{26A0} acceptance: \(statement) \u{2014} do NOT claim acceptance")
      if JavaScriptReading.isTruthy(claim["basis"]) {
        lines.append("  on the evidence of: \(JavaScriptReading.text(claim["basis"]))")
      }
    }
    lines.append("")

    for row in rows {
      let badge = statusBadge(status: row["status"], localStatus: row["local_status"])
      let word = JavaScriptReading.padEnd(badge.word, 9)
      lines.append("  \(badge.glyph) \(word) \(JavaScriptReading.text(row["row_id"]))")
      if let action = scanRowAction(row) {
        lines.append("      \u{2192} \(action)")
      }
    }

    lines += integrityErrorLines(status?["integrity_errors"]?.arrayValue ?? [])
    if let gate = data["gate"], JavaScriptReading.isTruthy(gate) {
      lines += gateLines(gate, rows: rows)
    }
    return lines
  }

  private static func integrityErrorLines(_ errors: [JSONValue]) -> [String] {
    guard !errors.isEmpty else {
      return []
    }
    let errorWord = errors.count == 1 ? "error" : "errors"
    var lines = ["", "integrity \(errorWord) \u{2014} \(errors.count):"]
    for error in errors {
      var place: [String] = []
      if JavaScriptReading.isTruthy(error["file_path"]) {
        place.append(JavaScriptReading.text(error["file_path"]))
      }
      if let line = JavaScriptReading.present(error["line"]) {
        place.append("line \(JavaScriptReading.text(line))")
      }
      let message = JavaScriptReading.isTruthy(error["message"])
        ? ": \(JavaScriptReading.text(error["message"]))"
        : ""
      lines.append("  \u{2717} \(JavaScriptReading.text(error["code"]))\(message)")
      if !place.isEmpty {
        lines.append("      at \(place.joined(separator: " "))")
      }
      if JavaScriptReading.isTruthy(error["remediation"]) {
        lines.append("      \u{2192} \(JavaScriptReading.text(error["remediation"]))")
      }
    }
    return lines
  }

  /// Whether the bar blocked; on a pass, how many required rows it covered;
  /// and a warning for every non-required row below the bar.
  private static func gateLines(
    _ gate: JSONValue,
    rows: [JSONValue],
  ) -> [String] {
    var lines = [""]
    let bar = JavaScriptReading.present(gate["required_bar"]).map(JavaScriptReading.text) ?? "?"
    if JavaScriptReading.isTruthy(gate["blocked"]) {
      let offenders = (gate["offending_rows"]?.arrayValue ?? [])
        .map { row in
          JavaScriptReading.text(row["row_id"])
        }
        .joined(separator: ", ")
      lines.append("\u{2717} gate BLOCKED (bar: \(bar)) \u{2014} \(offenders)")
    } else {
      let requiredMet = rows.filter { row in
        row["required_for_release"] == .bool(true)
          && isGreen(status: row["status"], localStatus: row["local_status"])
      }.count
      let behaviourWord = requiredMet == 1 ? "behaviour" : "behaviours"
      lines.append(
        "\u{2713} gate passed \u{2014} \(requiredMet) required \(behaviourWord) meet \(bar).",
      )
    }
    for row in gate["ungated_below_bar"]?.arrayValue ?? [] {
      let localStatus = JavaScriptReading.present(row["local_status"])
      let state = if row["status"] == .string("UNPROVEN"), JavaScriptReading.isTruthy(localStatus) {
        "\(JavaScriptReading.text(row["status"]))/\(JavaScriptReading.text(localStatus))"
      } else {
        JavaScriptReading.present(row["status"]).map(JavaScriptReading.text) ?? "below bar"
      }
      lines.append(
        "\u{26A0} \(JavaScriptReading.text(row["row_id"])) is \(state) but NOT gated \u{2014} "
          + "mark it `approval_policy.required_for_release: true` to enforce it.",
      )
    }
    return lines
  }
}

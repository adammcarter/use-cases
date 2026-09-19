import UseCasesCore

extension TrustRenderer {
  /// `renderRecover`: whether the target came back to green, then one line per
  /// row, with the next action only for a row still not green.
  static func recoverLines(_ data: JSONValue) -> [String] {
    let rows = data["status"]?["rows"]?.arrayValue ?? []
    let target = JavaScriptReading.present(data["target"]).map(JavaScriptReading.text)
      ?? "the target row"
    var lines = [
      data["recovered"] == .bool(true)
        ? "\u{2713} recovered \(target) \u{2014} back to green."
        : "\u{2717} could NOT recover \(target) \u{2014} still not green.",
      "",
    ]
    for row in rows {
      let badge = statusBadge(status: row["status"], localStatus: row["local_status"])
      let word = JavaScriptReading.padEnd(badge.word, 14)
      lines.append("  \(badge.glyph) \(word) \(JavaScriptReading.text(row["row_id"]))")
      if !isGreen(status: row["status"], localStatus: row["local_status"]),
         let action = scanRowAction(row)
      {
        lines.append("      \u{2192} \(action)")
      }
    }
    return lines
  }
}

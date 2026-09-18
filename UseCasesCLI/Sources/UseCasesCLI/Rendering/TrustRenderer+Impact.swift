import UseCasesCore

extension TrustRenderer {
  //: @use-case:lifecycle.signals.impact_leads_with_the_union
  /// `renderImpact`: the headline counts span-hit and file-touched rows
  /// TOGETHER, because a touched row is impacted until re-verified; then each
  /// with the command to re-verify it, then broken bindings.
  static func impactLines(_ data: JSONValue) -> [String] {
    let impacted = JavaScriptReading.present(data["impacted"])?.arrayValue ?? []
    let touched = JavaScriptReading.present(data["touched"])?.arrayValue ?? []
    let broken = JavaScriptReading.present(data["broken_bindings"])?.arrayValue ?? []
    var lines: [String] = []

    let affected = impacted.count + touched.count
    let word = affected == 1 ? "behaviour" : "behaviours"
    lines.append(affected == 0
      ? "0 behaviours impacted by your change"
      : "\(affected) \(word) may be impacted by your change "
      + "(\(impacted.count) span-hit, \(touched.count) file-touched) \u{2014} re-verify these")
    if JavaScriptReading.isTruthy(data["base"]) {
      lines.append("(diff base: \(JavaScriptReading.text(data["base"])))")
    }
    lines.append("")
    if affected == 0 {
      lines.append(
        "  \u{00B7} nothing impacted \u{2014} no bound span overlaps your change, "
          + "and no bound file was touched",
      )
    }

    for binding in impacted {
      let rowIdentifier = JavaScriptReading.text(binding["row_id"])
      lines.append("  \u{2717} \(rowIdentifier)")
      lines.append(
        "      \u{2192} re-verify (span in \(JavaScriptReading.text(binding["file"]))); "
          + "run `use-cases verify --row \(rowIdentifier)`",
      )
    }

    lines += touchedLines(touched)
    lines += brokenLines(broken)
    return lines
  }

  //: @use-case:end lifecycle.signals.impact_leads_with_the_union

  private static func touchedLines(_ touched: [JSONValue]) -> [String] {
    var lines: [String] = []
    if !touched.isEmpty {
      lines.append("")
      lines.append(
        "touched (file changed, span not hit) \u{2014} \(touched.count), "
          + "treat as affected until re-verified:",
      )
      for binding in touched {
        let rowIdentifier = JavaScriptReading.text(binding["row_id"])
        lines.append("  ? \(rowIdentifier) (\(JavaScriptReading.text(binding["file"])))")
        lines
          .append(
            "      \u{2192} re-verify to be sure; run `use-cases verify --row \(rowIdentifier)`",
          )
      }
    }

    return lines
  }

  private static func brokenLines(_ broken: [JSONValue]) -> [String] {
    var lines: [String] = []
    if !broken.isEmpty {
      lines.append("")
      lines.append("broken bindings (marked code moved/gone) \u{2014} \(broken.count):")
      for binding in broken {
        lines.append(
          "  \u{2717} \(JavaScriptReading.text(binding["row_id"])) \u{2014} "
            + "\(JavaScriptReading.text(binding["reason"])) "
            + "(\(JavaScriptReading.text(binding["file"]))); re-bind it",
        )
      }
    }
    return lines
  }
}

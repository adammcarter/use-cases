import UseCasesCore

/// Turns a result envelope into output bytes (packages/cli/src/render.ts).
///
/// `--json` is the wire form plus a newline. Otherwise a generic human view:
/// a status line, a YAML-ish dump of `data`, the diagnostics with where each
/// points, and a pointer to `--json`.
///
/// The TypeScript also has bespoke human views for the trust commands (`scan`,
/// `verify`, `impact`, `recover`, `showcase status`) and for an approval
/// request. They land with those commands in later subrows; until then those
/// commands only ever return error envelopes, which the TypeScript renders with
/// this generic view too.
enum EnvelopeRenderer {
  static let footer = "Add --json for the full machine-readable result envelope."

  static func render(
    _ envelope: JSONValue,
    isJSON: Bool,
  ) -> String {
    if isJSON {
      return JSONWriter.encode(envelope) + "\n"
    }
    return renderHuman(envelope)
  }

  private static func renderHuman(_ envelope: JSONValue) -> String {
    let mark = envelope["ok"] == .bool(true) ? "✓" : "✗"
    let command = envelope["command"].map(scalarText) ?? "undefined"
    let incomplete = envelope["complete"] == .bool(false) ? "  (incomplete)" : ""
    var lines = ["\(mark) \(command)\(incomplete)"]

    lines += HumanValueDumper.lines(for: envelope["data"], depth: 1)

    let diagnostics = envelope["diagnostics"]?.arrayValue ?? []
    if !diagnostics.isEmpty {
      lines.append("")
      for diagnostic in diagnostics {
        lines += diagnosticLines(diagnostic)
      }
    }

    lines.append("")
    lines.append(footer)
    return lines.joined(separator: "\n") + "\n"
  }

  private static func diagnosticLines(_ diagnostic: JSONValue) -> [String] {
    let severity = diagnostic["severity"].flatMap(\.stringValue) ?? "info"
    let glyph = switch severity {
    case "error": "\u{2717}"
    case "warning": "!"
    default: "\u{00B7}"
    }
    let code = diagnostic["code"].map(scalarText) ?? "undefined"
    let message = diagnostic["message"].map(scalarText) ?? "undefined"
    var lines = ["  \(glyph) \(code): \(message)"]

    var location: [String] = []
    for key in ["source_path", "json_pointer"] {
      if let text = diagnostic[key]?.stringValue, !text.isEmpty {
        location.append(text)
      }
    }
    if let entity = diagnostic["entity_id"]?.stringValue, !entity.isEmpty {
      location.append("(row \(entity))")
    }
    if !location.isEmpty {
      lines.append("      at \(location.joined(separator: " "))")
    }
    return lines
  }

  /// JavaScript's `String(value)` for a scalar.
  static func scalarText(_ value: JSONValue) -> String {
    switch value {
    case .null: "null"
    case let .bool(flag): flag ? "true" : "false"
    case let .number(number): JavaScriptNumber.text(number)
    case let .string(text): text
    case let .array(items): items.map(arrayMemberText).joined(separator: ",")
    case .object: "[object Object]"
    }
  }

  /// `Array.prototype.join` spells null members as empty.
  private static func arrayMemberText(_ value: JSONValue) -> String {
    value == .null ? "" : scalarText(value)
  }
}

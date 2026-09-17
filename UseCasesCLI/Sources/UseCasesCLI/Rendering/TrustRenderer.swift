import UseCasesCore

/// The human views of the daily trust commands (packages/cli/src/trustRender.ts):
/// `scan`, `verify`, `impact`, `recover` and `showcase status`, plus the
/// approval request object. A rendering layer only: it reads the envelope a
/// command already produced and recomputes nothing.
enum TrustRenderer {
  static let commands: Set = [
    "markers.scan",
    "markers.verify",
    "markers.impact",
    "markers.recover",
    "showcase.status",
  ]

  /// `renderTrustHuman`: the command's own view, or nil so the generic dumper
  /// runs — for a command outside the set, and for an envelope whose data lacks
  /// the command's shape, which is how a genuine error keeps its diagnostics
  /// view. A non-green trust result renders here.
  static func render(_ envelope: JSONValue) -> String? {
    guard let command = envelope["command"]?.stringValue, commands.contains(command),
          let data = envelope["data"], case .object = data
    else {
      return nil
    }
    guard let body = body(command: command, data: data) else {
      return nil
    }
    // A failed command never reads as unqualified success: a leading banner,
    // then the diagnostics that say why.
    let failed = envelope["ok"] == .bool(false)
    let banner = failed ? [failureBanner(command: command, data: data)] : []
    let why = failed ? diagnosticLines(envelope["diagnostics"]) : []
    let trimmedBody = !why.isEmpty && body.last == "" ? Array(body.dropLast()) : body
    let lines = banner + trimmedBody + why + ["", EnvelopeRenderer.footer]
    return lines.joined(separator: "\n") + "\n"
  }

  /// The command's view of `data`, or nil when `data` lacks its shape.
  private static func body(
    command: String,
    data: JSONValue,
  ) -> [String]? {
    switch command {
    case "markers.scan":
      guard case .object = data["status"] else {
        return nil
      }
      return scanLines(data)
    case "markers.verify":
      guard case .array = data["results"] else {
        return nil
      }
      return verifyLines(data)
    case "markers.impact":
      guard case .array = data["impacted"] else {
        return nil
      }
      return impactLines(data)
    case "markers.recover":
      guard case .bool = data["recovered"] else {
        return nil
      }
      return recoverLines(data)
    default:
      guard case .string = data["run_id"], case .string = data["approval_state"] else {
        return nil
      }
      return showcaseStatusLines(data)
    }
  }

  /// A glyph and word per status; a keyless local pass is the daily green.
  static func statusBadge(
    status: JSONValue?,
    localStatus: JSONValue?,
  ) -> (glyph: String, word: String) {
    switch status?.stringValue {
    case "FRESH":
      ("\u{2713}", "FRESH")
    case "SUSPECT":
      ("\u{2717}", "SUSPECT")
    case "INVALID":
      ("\u{2717}", "INVALID")
    case "UNPROVEN":
      localStatus == .string("VERIFIED_LOCAL")
        ? ("\u{2713}", "VERIFIED_LOCAL")
        : ("\u{00B7}", "UNPROVEN")
    case "UNBOUND":
      ("\u{00B7}", "UNBOUND")
    default:
      ("\u{00B7}", JavaScriptReading.text(status))
    }
  }

  static func isGreen(
    status: JSONValue?,
    localStatus: JSONValue?,
  ) -> Bool {
    status == .string("FRESH")
      || (status == .string("UNPROVEN") && localStatus == .string("VERIFIED_LOCAL"))
  }

  /// The action for a non-green row: the daily verb `uc recover` for drifted
  /// or unverified rows.
  static func scanRowAction(_ row: JSONValue) -> String? {
    let status = row["status"]
    let rowIdentifier = JavaScriptReading.text(row["row_id"])
    if isGreen(status: status, localStatus: row["local_status"]) {
      return nil
    }
    switch status?.stringValue {
    case "SUSPECT", "UNPROVEN":
      return "run `uc recover --row \(rowIdentifier)`"
    case "INVALID":
      return "resolve the binding integrity errors, then re-run `uc scan`"
    case "UNBOUND":
      return "bind it with `uc bind --row \(rowIdentifier) \u{2026}`"
    default:
      return JavaScriptReading.isTruthy(row["required_action"])
        ? "run `\(JavaScriptReading.text(row["required_action"]))`"
        : nil
    }
  }

  /// The failed command's diagnostics that carry a message, in the generic
  /// view's glyphs; empty when none do.
  private static func diagnosticLines(_ diagnostics: JSONValue?) -> [String] {
    let usable = (diagnostics?.arrayValue ?? []).filter { diagnostic in
      guard let message = diagnostic["message"]?.stringValue else {
        return false
      }
      return !message.isEmpty
    }
    guard !usable.isEmpty else {
      return []
    }
    return [""] + usable.map { diagnostic in
      let glyph = switch diagnostic["severity"]?.stringValue {
      case "error": "\u{2717}"
      case "warning": "!"
      default: "\u{00B7}"
      }
      let code = JavaScriptReading.isTruthy(diagnostic["code"])
        ? "\(JavaScriptReading.text(diagnostic["code"])): "
        : ""
      return "  \(glyph) \(code)\(JavaScriptReading.text(diagnostic["message"]))"
    }
  }

  private static func failureBanner(
    command: String,
    data: JSONValue,
  ) -> String {
    let verb = command.hasPrefix("markers.")
      ? String(command.dropFirst("markers.".count))
      : command
    let suffix = data["exit_code"]?.numberValue.map { code in
      " (exit \(JavaScriptNumber.text(code)))"
    } ?? ""
    return "\u{2717} \(verb) FAILED\(suffix) \u{2014} details below; add --json for the "
      + "machine-readable envelope.\n"
  }
}

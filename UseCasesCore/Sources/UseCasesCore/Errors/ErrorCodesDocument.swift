/// Renders `docs/reference/error-codes.md` from the registry
/// (packages/core/src/errors/render.ts).
public enum ErrorCodesDocument {
  /// The full page, with its trailing newline.
  public static func render() -> String {
    var lines: [String] = [
      "<!-- GENERATED FILE — do not edit by hand.",
      "     Regenerate with `node packages/core/scripts/generate-error-codes.mjs`",
      "     (source of truth: packages/core/src/errors/registry.ts). -->",
      "",
      "# Error Codes",
      "",
      "Stable `UCM_*` error codes are part of the [public API](./stability.md). Each",
      "code below is a versioned contract: a code is only removed or repurposed in a",
      "**major** release; new codes ship additively in a **minor**. Diagnostics carry",
      "the code in their `code` field.",
      "",
      "There are **\(PublicErrorRegistry.codes.count)** codes across "
        + "**\(PublicErrorSurface.allCases.count)** surfaces.",
      "",
    ]

    for surface in PublicErrorSurface.allCases {
      let entries = PublicErrorRegistry.codes.compactMap(PublicErrorRegistry.entry(for:))
        .filter { entry in
          entry.surface == surface
        }
      if entries.isEmpty {
        continue
      }
      lines += ["## \(surface.title)", "", "| Code | Severity | Message |", "|---|---|---|"]
      for entry in entries {
        let severity = entry.severity.rawValue
        lines.append("| `\(entry.code.rawValue)` | \(severity) | \(escapeCell(entry.message)) |")
      }
      lines.append("")
    }

    return lines.joined(separator: "\n")
  }

  /// `value.replace(/\|/g, "\\|")`.
  static func escapeCell(_ value: String) -> String {
    value.replacingOccurrences(of: "|", with: "\\|")
  }
}

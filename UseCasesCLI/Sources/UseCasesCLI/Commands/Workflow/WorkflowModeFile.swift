/// Reads and rewrites `default_workflow_mode` in the text of `use-cases.yml`
/// (packages/cli/src/commands/workflow.ts), reproducing the TypeScript's
/// regular expressions exactly: `/^default_workflow_mode:\s*([a-z_]+)/m`, with
/// JavaScript's multiline `^`, its `\s` (which crosses line breaks), and
/// `trimEnd` before an appended line.
enum WorkflowModeFile {
  static let key = "default_workflow_mode:"
  static let defaultMode = "continuous"
  static let modes = ["continuous", "backfill", "showcase_only", "audit_only", "custom"]

  /// The first line-anchored mode, or `continuous`.
  static func mode(in source: String) -> String {
    guard let match = firstMatch(in: source) else {
      return defaultMode
    }
    return String(String.UnicodeScalarView(match.mode))
  }

  /// The source with the first mode replaced, or with the mode appended when no
  /// line starts with the key. A key whose value the pattern cannot read leaves
  /// the source as it is.
  static func replacingMode(
    in source: String,
    with mode: String,
  ) -> String {
    let scalars = Array(source.unicodeScalars)
    let hasKeyLine = lineStarts(in: scalars).contains { start in
      hasKey(scalars, at: start)
    }
    guard hasKeyLine else {
      return trimmingEnd(source) + "\n\(key) \(mode)\n"
    }
    guard let match = firstMatch(in: source) else {
      return source
    }
    var rewritten = String.UnicodeScalarView(scalars[..<match.start])
    rewritten.append(contentsOf: "\(key) \(mode)".unicodeScalars)
    rewritten.append(contentsOf: scalars[match.end...])
    return String(rewritten)
  }

  /// A requested mode with dashes read as underscores, or nil when it is not
  /// one of the modes.
  static func canonicalMode(_ value: String?) -> String? {
    guard let value, !value.isEmpty else {
      return nil
    }
    let normalized = value.replacingOccurrences(of: "-", with: "_")
    return modes.contains(normalized) ? normalized : nil
  }

  private struct Match {
    let start: Int
    let end: Int
    let mode: ArraySlice<Unicode.Scalar>
  }

  private static func firstMatch(in source: String) -> Match? {
    let scalars = Array(source.unicodeScalars)
    for start in lineStarts(in: scalars) where hasKey(scalars, at: start) {
      var index = start + key.unicodeScalars.count
      while index < scalars.count, isJavaScriptWhitespace(scalars[index]) {
        index += 1
      }
      let modeStart = index
      while index < scalars.count, isModeCharacter(scalars[index]) {
        index += 1
      }
      if index > modeStart {
        return Match(start: start, end: index, mode: scalars[modeStart ..< index])
      }
    }
    return nil
  }

  private static func lineStarts(in scalars: [Unicode.Scalar]) -> [Int] {
    var starts = [0]
    for (index, scalar) in scalars.enumerated() where isLineTerminator(scalar) {
      starts.append(index + 1)
    }
    return starts
  }

  private static func hasKey(
    _ scalars: [Unicode.Scalar],
    at start: Int,
  ) -> Bool {
    let keyScalars = Array(key.unicodeScalars)
    guard start + keyScalars.count <= scalars.count else {
      return false
    }
    return scalars[start ..< start + keyScalars.count].elementsEqual(keyScalars)
  }

  private static func isModeCharacter(_ scalar: Unicode.Scalar) -> Bool {
    ("a" ... "z").contains(scalar) || scalar == "_"
  }

  private static func isLineTerminator(_ scalar: Unicode.Scalar) -> Bool {
    ["\n", "\r", "\u{2028}", "\u{2029}"].contains(scalar)
  }

  /// JavaScript's `\s`: WhiteSpace and LineTerminator.
  static func isJavaScriptWhitespace(_ scalar: Unicode.Scalar) -> Bool {
    switch scalar.value {
    case 0x09 ... 0x0D, 0x20, 0xA0, 0x1680, 0x2000 ... 0x200A, 0x2028, 0x2029, 0x202F, 0x205F,
         0x3000, 0xFEFF:
      true
    default:
      false
    }
  }

  private static func trimmingEnd(_ text: String) -> String {
    var scalars = Array(text.unicodeScalars)
    while let last = scalars.last, isJavaScriptWhitespace(last) {
      scalars.removeLast()
    }
    return String(String.UnicodeScalarView(scalars))
  }
}

import Foundation

public enum AppendOnlyViolationKind: String, Equatable, Sendable {
  /// An existing line's text changed; a reorder shows up as an edit.
  case edited
  /// An existing line is gone because the new content is shorter.
  case deleted
}

public struct AppendOnlyViolation: Equatable, Sendable {
  public let kind: AppendOnlyViolationKind
  /// 0-based index into the old lines where the prefix first breaks.
  public let index: Int
  public let oldLine: String
  /// Nil when the line was deleted.
  public let newLine: String?
  public let message: String

  var jsonValue: JSONValue {
    .object(JSONObject([
      ("kind", .string(kind.rawValue)),
      ("index", .number(Double(index))),
      ("old_line", .string(oldLine)),
      ("new_line", newLine.map(JSONValue.string) ?? .null),
      ("message", .string(message)),
    ]))
  }
}

public enum AppendOnlyResult: Equatable, Sendable {
  case holds
  case violated(AppendOnlyViolation)

  /// `{ ok: true }` or `{ ok: false, violation }`.
  var jsonValue: JSONValue {
    switch self {
    case .holds:
      .object(JSONObject([("ok", .bool(true))]))
    case let .violated(violation):
      .object(JSONObject([("ok", .bool(false)), ("violation", violation.jsonValue)]))
    }
  }
}

/// Append-only discipline for JSONL ledgers (appendOnly.ts): the old content
/// must be an unchanged PREFIX of the new. The only impure piece is the read of
/// a file's base-ref version through `git show`.
public enum AppendOnly {
  /// `oldLines` must equal the leading prefix of `newLines`, code unit for code
  /// unit — a canonically equivalent respelling is an edit.
  public static func check(
    oldLines: [String],
    newLines: [String],
  ) -> AppendOnlyResult {
    for (index, oldLine) in oldLines.enumerated() {
      guard index < newLines.count else {
        return .violated(AppendOnlyViolation(
          kind: .deleted,
          index: index,
          oldLine: oldLine,
          newLine: nil,
          message: "existing line \(index + 1) was deleted; the registry is append-only",
        ))
      }
      guard JavaScriptString.identical(newLines[index], oldLine) else {
        return .violated(AppendOnlyViolation(
          kind: .edited,
          index: index,
          oldLine: oldLine,
          newLine: newLines[index],
          message: "existing line \(index + 1) was edited or reordered; "
            + "the registry is append-only",
        ))
      }
    }
    return .holds
  }

  /// Content lines, dropping the single empty segment a trailing newline
  /// leaves. Interior blank lines are kept so a blank-line edit is not hidden.
  public static func splitJSONLines(_ text: String) -> [String] {
    guard !text.isEmpty else {
      return []
    }
    var lines = JavaScriptString.split(text, on: CodeUnits.lineFeed)
    if lines.last == "" {
      lines.removeLast()
    }
    return lines
  }

  /// `git show <base-ref>:<path>`; "" when the path does not exist at the ref
  /// (a file added on this branch). Any other git failure is raised.
  public static func readBaseReferenceFile(
    baseReference: String,
    path: String,
    workingDirectory: String?,
    runner: some GitRunning = GitProcessRunner(),
  ) throws(GitError) -> String {
    do throws(GitError) {
      return try runner.run(
        ["show", "\(baseReference):\(path)"],
        workingDirectory: workingDirectory,
      )
    } catch {
      let detail = error.standardError ?? error.message
      if isAbsentAtBase(detail) {
        return ""
      }
      let trimmed = JavaScriptString.trim(detail)
      throw .baseReferenceUnreadable(
        message: "git show \(baseReference):\(path) failed: "
          + (trimmed.isEmpty ? "unknown error" : trimmed),
      )
    }
  }

  /// The current JSONL text against its base-ref version.
  public static func checkAgainstBaseReference(
    baseReference: String,
    path: String,
    currentText: String,
    workingDirectory: String?,
    runner: some GitRunning = GitProcessRunner(),
  ) throws(GitError) -> AppendOnlyResult {
    let oldText = try readBaseReferenceFile(
      baseReference: baseReference,
      path: path,
      workingDirectory: workingDirectory,
      runner: runner,
    )
    return check(oldLines: splitJSONLines(oldText), newLines: splitJSONLines(currentText))
  }

  /// `/does not exist in|exists on disk, but not in/i`. Without the `u` flag a
  /// JavaScript `i` pattern folds only ASCII letters onto this ASCII pattern.
  private static func isAbsentAtBase(_ text: String) -> Bool {
    let folded = text.utf16.map { unit in
      (0x41 ... 0x5A).contains(unit) ? unit + 0x20 : unit
    }
    return ["does not exist in", "exists on disk, but not in"].contains { pattern in
      let needle = Array(pattern.utf16)
      guard folded.count >= needle.count else {
        return false
      }
      return (0 ... folded.count - needle.count).contains { start in
        CodeUnits.hasPrefix(folded, needle, at: start)
      }
    }
  }
}

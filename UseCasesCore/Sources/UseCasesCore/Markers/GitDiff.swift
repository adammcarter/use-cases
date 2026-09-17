/// A 1-based inclusive line range.
public struct LineRange: Equatable, Sendable {
  public let startLine: Int
  public let endLine: Int

  public init(
    startLine: Int,
    endLine: Int,
  ) {
    self.startLine = startLine
    self.endLine = endLine
  }

  var jsonValue: JSONValue {
    .object(JSONObject([
      ("start_line", .number(Double(startLine))),
      ("end_line", .number(Double(endLine))),
    ]))
  }
}

public enum ChangeKind: String, Equatable, Sendable {
  case added
  case modified
  case deleted
  case renamed
}

/// One entry of `git diff --name-status -M -z`.
public struct GitDiffChange: Equatable, Sendable {
  public let change: ChangeKind
  /// The destination (current) path.
  public let file: String
  /// The source path of a rename or copy, else nil.
  public let oldFile: String?

  var jsonValue: JSONValue {
    .object(JSONObject([
      ("change", .string(change.rawValue)),
      ("file", .string(file)),
      ("old_file", oldFile.map(JSONValue.string) ?? .null),
    ]))
  }
}

/// A changed file and the NEW-side line ranges its hunks touched.
public struct ChangedFile: Equatable, Sendable {
  public let change: GitDiffChange
  public let ranges: [LineRange]

  var jsonValue: JSONValue {
    var object = change.jsonValue.objectValue ?? JSONObject()
    object["ranges"] = .array(ranges.map(\.jsonValue))
    return .object(object)
  }
}

public struct CollectedDiff: Equatable, Sendable {
  /// "HEAD", the ref, or "HEAD (staged)".
  public let base: String
  public let files: [ChangedFile]

  var jsonValue: JSONValue {
    .object(JSONObject([("base", .string(base)), ("files", .array(files.map(\.jsonValue)))]))
  }
}

/// Read-only git-diff plumbing for `uc impact` (gitDiff.ts): which files
/// changed, and which new line ranges the change touched.
public enum GitDiff {
  public static func rangesOverlap(
    _ first: LineRange,
    _ second: LineRange,
  ) -> Bool {
    first.startLine <= second.endLine && second.startLine <= first.endLine
  }

  /// NUL-framed `status\0path` or `status\0old\0new`. A copy reads as an add of
  /// its destination; a malformed tail stops parsing rather than emitting a
  /// partial entry.
  public static func parseNameStatus(_ text: String) -> [GitDiffChange] {
    let fields = JavaScriptString.split(text, on: 0).filter { field in
      !field.isEmpty
    }
    var changes: [GitDiffChange] = []
    var index = 0
    while index < fields.count {
      let code = fields[index].utf16.first
      if code == 0x52 || code == 0x43 {
        guard index + 2 < fields.count else {
          break
        }
        changes.append(GitDiffChange(
          change: code == 0x52 ? .renamed : .added,
          file: fields[index + 2],
          oldFile: fields[index + 1],
        ))
        index += 3
        continue
      }
      guard index + 1 < fields.count else {
        break
      }
      let change: ChangeKind = code == 0x41 ? .added : code == 0x44 ? .deleted : .modified
      changes.append(GitDiffChange(change: change, file: fields[index + 1], oldFile: nil))
      index += 2
    }
    return changes
  }

  /// The NEW-side range of every `@@ -a[,b] +c[,d] @@` header; a pure deletion
  /// (new count 0) adds none.
  public static func parseUnifiedZeroHunks(_ diff: String) -> [LineRange] {
    JavaScriptString.split(diff, on: CodeUnits.lineFeed).compactMap { line in
      guard let header = HunkHeader(line), header.lineCount > 0 else {
        return nil
      }
      return LineRange(startLine: header.start, endLine: header.start + header.lineCount - 1)
    }
  }

  /// `git diff --cached HEAD` when staged, else `git diff <base ?? HEAD>`; the
  /// name-status list, then each non-deleted file's zero-context hunks.
  public static func collectChangedFiles(
    base: String?,
    staged: Bool,
    workingDirectory: String?,
    runner: some GitRunning = GitProcessRunner(),
  ) throws(GitError) -> CollectedDiff {
    let prefix = staged ? ["diff", "--cached", "HEAD"] : ["diff", base ?? "HEAD"]
    let label = staged ? "HEAD (staged)" : base ?? "HEAD"
    let nameStatus = try runner.run(
      prefix + ["--name-status", "-M", "-z"],
      workingDirectory: workingDirectory,
    )
    var files: [ChangedFile] = []
    for change in parseNameStatus(nameStatus) {
      guard change.change != .deleted else {
        files.append(ChangedFile(change: change, ranges: []))
        continue
      }
      let body = try runner.run(
        prefix + ["--unified=0", "-M", "--", change.file],
        workingDirectory: workingDirectory,
      )
      files.append(ChangedFile(change: change, ranges: parseUnifiedZeroHunks(body)))
    }
    return CollectedDiff(base: label, files: files)
  }
}

/// `/^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@/`, ASCII digits only.
private struct HunkHeader {
  let start: Int
  let lineCount: Int

  init?(_ line: String) {
    var reader = HunkReader(units: Array(line.utf16))
    guard reader.expect("@@ -"), reader.digits() != nil else {
      return nil
    }
    if reader.expect(","), reader.digits() == nil {
      return nil
    }
    guard reader.expect(" +"), let start = reader.digits() else {
      return nil
    }
    var lineCount = 1
    if reader.expect(",") {
      guard let parsed = reader.digits() else {
        return nil
      }
      lineCount = parsed
    }
    guard reader.expect(" @@") else {
      return nil
    }
    self.start = start
    self.lineCount = lineCount
  }
}

private struct HunkReader {
  let units: [UInt16]
  var index = 0

  mutating func expect(_ literal: String) -> Bool {
    let needle = Array(literal.utf16)
    guard CodeUnits.hasPrefix(units, needle, at: index) else {
      return false
    }
    index += needle.count
    return true
  }

  /// One or more ASCII digits. A run too long for `Int` saturates; git never
  /// writes one.
  mutating func digits() -> Int? {
    let start = index
    var value = 0
    while index < units.count, CodeUnits.isASCIIDigit(units[index]) {
      let (shifted, overflowShift) = value.multipliedReportingOverflow(by: 10)
      let (added, overflowAdd) = shifted.addingReportingOverflow(Int(units[index] - 0x30))
      value = overflowShift || overflowAdd ? Int.max : added
      index += 1
    }
    return index > start ? value : nil
  }
}

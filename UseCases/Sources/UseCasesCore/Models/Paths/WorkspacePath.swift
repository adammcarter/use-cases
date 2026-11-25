/// A path relative to the workspace root, separated with `/` on every system (chapter 04).
///
/// It is stored exactly as written: equality, hashing and ordering compare the UTF-8 bytes,
/// so a name in one Unicode form is not the same path as the same name in another, and a
/// workspace sorts the same on every machine. The grammar is the schemas' `projectPath`, and a
/// path is spelled canonically: no `.` or empty segment, so `./bar`, `a//b` and `a/` are
/// refused, never normalised. The one exception is `.` alone, the workspace root.
struct WorkspacePath: Hashable, Comparable, Sendable, CustomStringConvertible {
  let text: String

  /// Reads a path, refusing an absolute path, a drive letter, a `..`, `.` or empty segment, a
  /// backslash, an empty value and a control character. `.` alone is the workspace root.
  init(validating text: String) throws(WorkspacePathError) {
    try Self.checkRules(of: text)
    self.text = text
  }

  /// Whether this is the workspace root itself, written `.`.
  var isRoot: Bool {
    text == "."
  }

  /// The segments between the `/` separators, in order.
  var segments: [String] {
    text.splitOnScalar("/")
  }

  var description: String {
    text
  }

  static func == (
    lhs: WorkspacePath,
    rhs: WorkspacePath,
  ) -> Bool {
    lhs.text.isExactlyEqual(to: rhs.text)
  }

  static func < (
    lhs: WorkspacePath,
    rhs: WorkspacePath,
  ) -> Bool {
    lhs.text.precedesExactly(rhs.text)
  }

  func hash(into hasher: inout Hasher) {
    text.hashExactly(into: &hasher)
  }

  /// The rules every authored path obeys, shared with the path pattern dialect.
  static func checkRules(of text: String) throws(WorkspacePathError) {
    guard !text.isEmpty else {
      throw .empty
    }

    if let control = text.unicodeScalars.first(where: { $0.value < 0x20 || $0.value == 0x7F }) {
      throw .controlCharacter(control, within: text)
    }

    if text.unicodeScalars.contains("\\") {
      throw .backslash(text)
    }

    if text.unicodeScalars.first == "/" {
      throw .absolute(text)
    }

    if startsWithDriveLetter(text) {
      throw .driveLetter(text)
    }

    let segments = text.splitOnScalar("/")

    if segments.contains("..") {
      throw .parentSegment(text)
    }

    if text == "." {
      return
    }

    if segments.contains(where: { $0.isEmpty || $0 == "." }) {
      throw .notCanonical(
        text,
        canonical: canonicalSpelling(of: segments),
      )
    }
  }

  /// The spelling without `.` and empty segments, when that is itself a valid path.
  private static func canonicalSpelling(of segments: [String]) -> String? {
    var kept: [String] = []

    for segment in segments where !segment.isEmpty && segment != "." {
      kept.append(segment)
    }

    let candidate = kept.isEmpty ? "." : kept.joined(separator: "/")

    guard (try? checkRules(of: candidate)) != nil else {
      return nil
    }

    return candidate
  }

  private static func startsWithDriveLetter(_ text: String) -> Bool {
    let scalars = Array(text.unicodeScalars.prefix(2))

    guard scalars.count == 2, scalars[1] == ":" else {
      return false
    }

    switch scalars[0].value {
    case 0x41 ... 0x5A, 0x61 ... 0x7A:
      return true
    default:
      return false
    }
  }
}

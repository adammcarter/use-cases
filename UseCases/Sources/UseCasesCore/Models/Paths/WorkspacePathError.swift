/// Why a piece of text is not a workspace-relative path (chapters 04 and 09).
enum WorkspacePathError: Error, Equatable, Sendable {
  /// Nothing was written.
  case empty

  /// It begins with `/`.
  case absolute(String)

  /// It begins with a drive letter, such as `C:`.
  case driveLetter(String)

  /// A segment is `..`, which would leave the workspace root or hide where the path goes.
  case parentSegment(String)

  /// It holds a backslash; paths always separate with `/`.
  case backslash(String)

  /// It holds a control character (U+0000 to U+001F, or U+007F).
  case controlCharacter(Unicode.Scalar, within: String)

  /// A name on disk is not valid UTF-8, so it is not text at all; the text is the name with its
  /// non-ASCII bytes escaped, for showing.
  case notUTF8(String)

  /// It has a `.` or an empty segment (`./bar`, `a//b`, `a/`); only the whole path `.` may be
  /// written with a `.`. A path is written in one canonical spelling and never normalised;
  /// `canonical` is that spelling, when there is one.
  case notCanonical(String, canonical: String?)
}

extension WorkspacePathError: CustomStringConvertible {
  /// The text that was refused, empty when none was written.
  var offendingText: String {
    switch self {
    case .empty:
      ""
    case let .absolute(text),
         let .driveLetter(text),
         let .parentSegment(text),
         let .backslash(text),
         let .controlCharacter(_, text),
         let .notUTF8(text),
         let .notCanonical(text, _):
      text
    }
  }

  /// What is wrong with it, without the text itself.
  var reason: String {
    switch self {
    case .empty:
      "a path cannot be empty"
    case .absolute:
      "it must be relative to the workspace root, not begin with '/'"
    case .driveLetter:
      "it must be relative to the workspace root, not begin with a drive letter"
    case .parentSegment:
      "it must stay inside the workspace, so no segment may be '..'"
    case .backslash:
      "paths separate with '/', never '\\'"
    case .notUTF8:
      "its name is not valid UTF-8"
    case let .controlCharacter(scalar, _):
      "it holds the control character '\(scalar.escaped(asASCII: true))'"
    case let .notCanonical(_, canonical?):
      "it is not spelled canonically; write '\(canonical)'"
    case .notCanonical(_, nil):
      "it is not spelled canonically; a segment cannot be empty or '.'"
    }
  }

  var description: String {
    "'\(offendingText)' is not a valid path: \(reason)"
  }
}

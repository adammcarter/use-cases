/// Configuration for comment-prefix resolution.
public struct CommentPrefixConfiguration: Equatable, Sendable {
  /// Extension (leading dot, lower-cased, e.g. `.swift`) to line-comment prefix,
  /// merged over ``CommentPrefix/defaults``; an entry here wins.
  public var extensions: [String: String]?

  public init(extensions: [String: String]? = nil) {
    self.extensions = extensions
  }
}

/// The comment-prefix resolver (spec section 1.1, Amendment 1).
///
/// The marker is `<line-comment-prefix>: @use-case:<payload>`, and the prefix
/// is not universal (`//` is invalid in Python), so it is resolved per file
/// extension. Identity only: this decides how a marker comment is written.
public enum CommentPrefix {
  /// The default extension to line-comment prefix map.
  public static let defaults: [String: String] = [
    // `//` languages.
    ".swift": "//", ".ts": "//", ".tsx": "//", ".js": "//", ".jsx": "//", ".mjs": "//",
    ".cjs": "//", ".c": "//", ".cc": "//", ".cpp": "//", ".cxx": "//", ".h": "//",
    ".hpp": "//", ".m": "//", ".mm": "//", ".java": "//", ".kt": "//", ".kts": "//",
    ".go": "//", ".rs": "//", ".scala": "//",
    // `#` languages.
    ".py": "#", ".rb": "#", ".sh": "#", ".bash": "#", ".zsh": "#", ".yaml": "#",
    ".yml": "#", ".toml": "#", ".pl": "#", ".r": "#",
  ]

  /// The lower-cased extension of a path, leading dot included; empty when the
  /// basename has none. A dotfile such as `.gitignore` has none.
  public static func fileExtension(_ filePath: String) -> String {
    let units = Array(filePath.utf16)
    let slash = max(
      units.lastIndex(of: CodeUnits.solidus) ?? -1,
      units.lastIndex(of: CodeUnits.reverseSolidus) ?? -1,
    )
    let base = units[(slash + 1)...]
    guard let dot = base.lastIndex(of: CodeUnits.fullStop), dot > base.startIndex else {
      return ""
    }
    return JavaScriptCase.lowercased(CodeUnits.string(base[dot...]))
  }

  /// The configured line-comment prefix for a file, or nil when the file cannot
  /// carry markers. An extensionless file whose `contents` open with `#!` is a
  /// shebang script and resolves to `#`.
  public static func resolve(
    filePath: String,
    configuration: CommentPrefixConfiguration? = nil,
    contents: String? = nil,
  ) -> String? {
    let fileExtension = fileExtension(filePath)
    guard !fileExtension.utf16.isEmpty else {
      if let contents, contents.utf16.starts(with: "#!".utf16) {
        return "#"
      }
      return nil
    }
    if let extensions = configuration?.extensions,
       let override = exactLookup(extensions, fileExtension)
    {
      return override
    }
    return exactLookup(defaults, fileExtension)
  }

  /// A dictionary lookup by exact code units, as a JavaScript property lookup
  /// is — `String` keys would otherwise match by canonical equivalence.
  private static func exactLookup(
    _ map: [String: String],
    _ key: String,
  ) -> String? {
    map.first { entry in
      entry.key.utf16.elementsEqual(key.utf16)
    }?.value
  }
}

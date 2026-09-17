/// Why validating the skill assets stopped with an error rather than a result.
/// Each case is an error the TypeScript lets escape.
public enum SkillAssetValidationError: Error, Equatable, Sendable {
  /// The skills directory could not be listed or a document read.
  case fileAccess(FileAccessError)
  /// A skill's frontmatter is an empty or `null` YAML document. The
  /// TypeScript reads `.name` off the null and V8 raises a TypeError.
  case nullFrontmatter

  /// node's error code; a TypeError carries none.
  public var code: String? {
    switch self {
    case let .fileAccess(error): error.code
    case .nullFrontmatter: nil
    }
  }

  public var message: String {
    switch self {
    case let .fileAccess(error): error.message
    case .nullFrontmatter: "Cannot read properties of null (reading 'name')"
    }
  }
}

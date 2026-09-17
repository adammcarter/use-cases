/// The public product identity reported by `--version`, MCP `serverInfo` and
/// every result envelope. Frozen by ADR 0007 decision 8 for the whole ladder.
public enum ProductVersion {
  /// The public product name.
  public static let productName = "@adammcarter/use-cases"

  /// The published version. Bumped to 0.8.0 only at the release row, so the
  /// Swift binary reports exactly what the TypeScript build reports until then.
  public static let version = "0.7.0"

  /// The workspace component id used when a repository's config sets none.
  /// This is matrix DATA, distinct from ``productName``.
  public static let defaultComponentIdentifier = "use-cases"

  /// The name and version pair carried in result envelopes.
  public struct VersionInfo: Codable, Sendable, Equatable {
    public let name: String
    public let version: String

    public init(
      name: String,
      version: String,
    ) {
      self.name = name
      self.version = version
    }
  }

  /// The current product identity.
  public static func versionInfo() -> VersionInfo {
    VersionInfo(name: productName, version: version)
  }
}

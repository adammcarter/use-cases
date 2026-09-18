/// The public product identity reported by `--version`, MCP `serverInfo` and
/// every result envelope. Frozen by ADR 0007 decision 8 for the whole ladder.
public enum ProductVersion {
  /// The public product name.
  public static let productName = "@adammcarter/use-cases"

  /// The published version. Bumped to 0.8.0 at the release row (ADR 0007
  /// decision 9, ladder row 11); up to that point the Swift binary reported
  /// exactly what the TypeScript build reported, which is how the port was
  /// held to byte parity. It must stay equal to the version in the three host
  /// manifests — `ProductVersionManifestParityTests` is what joins them.
  public static let version = "0.8.0"

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

/// The versions this build of Use Cases reports (chapter 16 §7).
public struct ProductVersion: Equatable, Sendable {
  /// The versions this build was made with.
  public static let current = ProductVersion(
    release: "0.1.0",
    contract: 1,
    store: 1,
  )

  /// This release of Use Cases.
  public let release: String

  /// The transformer contract version (chapter 10).
  public let contract: Int

  /// The version of the runs this build writes to the results store (chapter 12).
  public let store: Int

  /// Makes a description of a build's versions.
  public init(
    release: String,
    contract: Int,
    store: Int,
  ) {
    self.release = release
    self.contract = contract
    self.store = store
  }
}

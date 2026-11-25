import UseCasesCore

/// Who the server says it is when a host connects.
enum ServerIdentity {
  /// The server's name.
  static let name = "use-cases"

  /// The server's name for people.
  static let title = "Use Cases"

  /// The release `use-cases --version` prints (chapter 16 §7), from the same constant.
  static let version = ProductVersion.current.release
}

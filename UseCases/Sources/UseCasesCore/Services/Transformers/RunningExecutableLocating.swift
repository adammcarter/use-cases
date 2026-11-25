import Foundation

/// Says where the running `use-cases` program is, which is where the bundled transformers are
/// (chapter 10 §9).
///
/// Public so that a program built on the core, the MCP server, can find itself.
public protocol RunningExecutableLocating: Sendable {
  /// The location of the running executable as the system gives it, which may go through a
  /// symlink; `nil` when the system cannot say.
  func executableLocation() -> URL?
}

import Foundation

/// A real on-disk directory that deletes itself when the last reference goes away.
///
/// Filesystem behaviour is fast and deterministic, so tests use a real directory
/// rather than a mock (see `swift-test-writing`).
public final class TemporaryDirectory: Sendable {
  public let url: URL

  public init() throws {
    let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
      .appendingPathComponent("use-cases-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    // Resolve symlinks once so tests compare against the same realpath the
    // production containment check sees (macOS /var -> /private/var).
    url = URL(fileURLWithPath: base.path).resolvingSymlinksInPath()
  }

  deinit {
    try? FileManager.default.removeItem(at: url)
  }

  /// Create a subdirectory, returning its URL.
  public func makeDirectory(_ relativePath: String) throws -> URL {
    let target = url.appendingPathComponent(relativePath, isDirectory: true)
    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
    return target
  }

  /// Write `contents` to a file, creating intermediate directories.
  @discardableResult
  public func writeFile(
    _ relativePath: String,
    contents: String,
  ) throws -> URL {
    let target = url.appendingPathComponent(relativePath)
    try FileManager.default.createDirectory(
      at: target.deletingLastPathComponent(),
      withIntermediateDirectories: true,
    )
    try contents.write(to: target, atomically: true, encoding: .utf8)
    return target
  }

  /// Create a symlink at `relativePath` pointing at `destination`.
  @discardableResult
  public func makeSymlink(
    _ relativePath: String,
    to destination: URL,
  ) throws -> URL {
    let link = url.appendingPathComponent(relativePath)
    try FileManager.default.createDirectory(
      at: link.deletingLastPathComponent(),
      withIntermediateDirectories: true,
    )
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: destination)
    return link
  }
}

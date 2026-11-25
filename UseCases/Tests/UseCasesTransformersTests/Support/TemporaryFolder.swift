import Foundation

/// A real folder for one test, removed when the test lets go of it.
final class TemporaryFolder {
  let url: URL

  var path: String {
    url.path
  }

  init() throws {
    let base = FileManager.default.temporaryDirectory
      .appendingPathComponent("use-cases-transformers-tests-\(UUID().uuidString)")

    try FileManager.default.createDirectory(
      at: base,
      withIntermediateDirectories: true,
    )

    // The system's own spelling of the folder, so paths compare equal after symlinks resolve.
    url = base.resolvingSymlinksInPath()
  }

  deinit {
    try? FileManager.default.removeItem(at: url)
  }

  func write(
    _ path: String,
    _ text: String,
  ) throws {
    let file = url.appendingPathComponent(path)

    try FileManager.default.createDirectory(
      at: file.deletingLastPathComponent(),
      withIntermediateDirectories: true,
    )

    try Data(text.utf8).write(to: file)
  }

  func writeBytes(
    _ path: String,
    _ bytes: [UInt8],
  ) throws {
    let file = url.appendingPathComponent(path)

    try FileManager.default.createDirectory(
      at: file.deletingLastPathComponent(),
      withIntermediateDirectories: true,
    )

    try Data(bytes).write(to: file)
  }

  /// The absolute path of `path` inside the folder.
  func absolute(_ path: String) -> String {
    url.appendingPathComponent(path).path
  }
}

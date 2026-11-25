import Foundation

/// A real folder for one test, removed when the test lets go of it.
final class TemporaryFolder {
  let url: URL

  init() throws {
    let base = FileManager.default.temporaryDirectory
      .appendingPathComponent("use-cases-mcp-tests-\(UUID().uuidString)")

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
}

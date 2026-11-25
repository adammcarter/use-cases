import Foundation

/// Finds the published schemas in the design, `docs/schemas/authored` and
/// `docs/schemas/engine`, by walking up from a test file until a folder holds `docs`.
enum DocsSchemas {
  struct NotFound: Error {
    let searchedFrom: String
  }

  static func folder(from filePath: String = #filePath) throws -> URL {
    try folder(
      named: "authored",
      from: filePath,
    )
  }

  /// The schemas the results store is checked against, `docs/schemas/engine`.
  static func storeFolder(from filePath: String = #filePath) throws -> URL {
    try folder(
      named: "engine",
      from: filePath,
    )
  }

  private static func folder(
    named name: String,
    from filePath: String,
  ) throws -> URL {
    var directory = URL(fileURLWithPath: filePath).deletingLastPathComponent()

    while directory.path != "/" {
      let candidate = directory.appending(path: "docs/schemas/\(name)")
      if FileManager.default.fileExists(atPath: candidate.path) {
        return candidate
      }
      directory.deleteLastPathComponent()
    }

    throw NotFound(searchedFrom: filePath)
  }
}

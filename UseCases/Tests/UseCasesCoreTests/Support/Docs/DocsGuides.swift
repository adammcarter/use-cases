import Foundation

/// Finds the published guides in the design, `docs/guides`, by walking up from a test file
/// until a folder holds them.
enum DocsGuides {
  struct NotFound: Error {
    let searchedFrom: String
  }

  static func folder(from filePath: String = #filePath) throws -> URL {
    var directory = URL(fileURLWithPath: filePath).deletingLastPathComponent()

    while directory.path != "/" {
      let candidate = directory.appending(path: "docs/guides")
      if FileManager.default.fileExists(atPath: candidate.path) {
        return candidate
      }
      directory.deleteLastPathComponent()
    }

    throw NotFound(searchedFrom: filePath)
  }
}

import Foundation

/// Finds the design's `docs` folder by walking up from a test file until a folder holds it.
enum DocsFolder {
  struct NotFound: Error {
    let searchedFrom: String
  }

  static func url(from filePath: String = #filePath) throws -> URL {
    var directory = URL(fileURLWithPath: filePath).deletingLastPathComponent()

    while directory.path != "/" {
      let candidate = directory.appending(path: "docs/schemas/output")
      if FileManager.default.fileExists(atPath: candidate.path) {
        return directory.appending(path: "docs")
      }
      directory.deleteLastPathComponent()
    }

    throw NotFound(searchedFrom: filePath)
  }
}

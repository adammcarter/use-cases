import Foundation

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

/// Makes the private folder with `mkdtemp`, which creates it readable, writable and enterable by
/// this user alone (mode 0700).
struct TransformerScratchMaker: TransformerScratchMaking {
  private let parent: URL

  /// - Parameter parent: The folder the private folder is made in: the system's temporary folder
  ///   unless a test says otherwise.
  init(parent: URL = FileManager.default.temporaryDirectory) {
    self.parent = parent
  }

  func makeScratch() throws(TransformerScratchError) -> TransformerScratch {
    var template = Array(
      parent.appendingPathComponent("use-cases-transformer-XXXXXX").path.utf8CString,
    )

    guard let created = mkdtemp(&template) else {
      throw .unavailable(reason: String(cString: strerror(errno)))
    }

    return TransformerScratch(
      folder: URL(
        fileURLWithPath: String(cString: created),
        isDirectory: true,
      ),
    )
  }
}

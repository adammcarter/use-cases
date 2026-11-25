import Foundation

/// A transformer's private folder, holding the request the core writes and the response the
/// transformer writes (chapter 10 §10).
struct TransformerScratch: Equatable, Sendable {
  let folder: URL

  /// What the core writes and the transformer reads.
  var request: URL {
    folder.appendingPathComponent("request.json")
  }

  /// What the transformer writes and the core reads.
  var response: URL {
    folder.appendingPathComponent("response.json")
  }

  /// Writes the request, readable by this user only.
  func writeRequest(_ bytes: [UInt8]) throws(TransformerScratchError) {
    let written = FileManager.default.createFile(
      atPath: request.path,
      contents: Data(bytes),
      attributes: [.posixPermissions: 0o600],
    )

    guard written else {
      throw .unavailable(reason: "request.json could not be written")
    }
  }

  /// The bytes the transformer wrote; `nil` when it wrote nothing.
  func readResponse() throws(TransformerScratchError) -> [UInt8]? {
    guard FileManager.default.fileExists(atPath: response.path) else {
      return nil
    }

    do {
      return try Array(Data(contentsOf: response))
    } catch {
      throw .unavailable(reason: error.localizedDescription)
    }
  }

  /// Removes the folder and everything in it.
  func remove() {
    try? FileManager.default.removeItem(at: folder)
  }
}

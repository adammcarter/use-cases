import Foundation

/// A folder in the system's temporary folder that holds the kept copies of the attachments of a
/// request, and goes when the last request that holds it is let go of.
final class AttachmentSpoolFolder: Sendable {
  let url: URL

  /// Names the folder; it is made by whoever fills it.
  init() {
    url = FileManager.default.temporaryDirectory
      .appendingPathComponent("use-cases-attachments-\(UUID().uuidString)")
  }

  deinit {
    try? FileManager.default.removeItem(at: url)
  }
}

extension AttachmentSpoolFolder: Equatable {
  static func == (
    left: AttachmentSpoolFolder,
    right: AttachmentSpoolFolder,
  ) -> Bool {
    left === right
  }
}

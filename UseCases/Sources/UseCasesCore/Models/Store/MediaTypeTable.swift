/// The one fixed table that gives an attachment its media type from the ending of its file name
/// (chapter 12 §16). It is the same on every system: nothing is asked of the machine, and a file
/// whose ending is not in the table has no media type.
enum MediaTypeTable {
  /// Each ending with the dot it starts with, in lowercase.
  private static let entries: [(ending: String, mediaType: String)] = [
    (".png", "image/png"),
    (".jpg", "image/jpeg"),
    (".jpeg", "image/jpeg"),
    (".gif", "image/gif"),
    (".webp", "image/webp"),
    (".svg", "image/svg+xml"),
    (".pdf", "application/pdf"),
    (".txt", "text/plain"),
    (".log", "text/plain"),
    (".json", "application/json"),
    (".xml", "application/xml"),
    (".html", "text/html"),
    (".md", "text/markdown"),
    (".csv", "text/csv"),
    (".mp4", "video/mp4"),
    (".mov", "video/quicktime"),
    (".zip", "application/zip"),
  ]

  /// The media type of a file name, or `nil` when its ending is not in the table. The ending is
  /// matched without regard to case, and only for the letters A to Z: no other character is
  /// folded, so the answer does not depend on the system's language.
  static func mediaType(forFileNamed name: String) -> String? {
    let reversed = name.unicodeScalars.reversed().map(foldedToLowercase)

    return entries.first { entry in
      reversed.starts(with: entry.ending.unicodeScalars.reversed())
    }?.mediaType
  }

  private static func foldedToLowercase(_ scalar: Unicode.Scalar) -> Unicode.Scalar {
    guard scalar.value >= 0x41, scalar.value <= 0x5A else {
      return scalar
    }

    return Unicode.Scalar(scalar.value + 0x20) ?? scalar
  }
}

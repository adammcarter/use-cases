/// Where a linked region sits in its file (chapter 11 §89.5): the file and the zero-based byte
/// offsets of the span, end exclusive.
struct FingerprintLocator: Equatable, Sendable {
  let file: WorkspacePath
  let startByte: Int
  let endByte: Int

  /// The three members of a locator.
  var canonical: CanonicalValue {
    .members([
      "file": .string(file.text),
      "start_byte": .integer(startByte),
      "end_byte": .integer(endByte),
    ])
  }

  /// Sorts by file, then start, then end (§89.5).
  func precedes(_ other: FingerprintLocator) -> Bool {
    if file != other.file {
      return file < other.file
    }

    if startByte != other.startByte {
      return startByte < other.startByte
    }

    return endByte < other.endByte
  }
}

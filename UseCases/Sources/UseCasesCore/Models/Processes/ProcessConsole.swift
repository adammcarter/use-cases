/// What is kept of a command's stdout and stderr, written together in the order the command
/// wrote them (chapter 14 §10).
struct ProcessConsole: Equatable, Sendable {
  /// Nothing was written.
  static let empty = ProcessConsole(
    text: "",
    omittedByteCount: 0,
  )

  /// The kept output, decoded as UTF-8 with U+FFFD for each invalid sequence. A capture larger
  /// than the limit reads as its first half, the marker, and its last half.
  let text: String

  /// How many bytes were left out of the middle; 0 when everything was kept.
  let omittedByteCount: Int
}

/// How a region's two sentinels sit in the file (chapter 08 "The linked region").
enum MarkerMode: Hashable, Sendable {
  /// The start and the end are on different lines: the region is the whole lines between them.
  case line

  /// The start and the end are on one line: the region is the bytes between the two tokens.
  case sameLine
}

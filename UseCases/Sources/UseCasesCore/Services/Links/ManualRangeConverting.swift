/// Turns a manual binding's range into the lines and bytes it selects in a file (chapter 08
/// "Manual bindings", chapter 11 §89.5).
protocol ManualRangeConverting: Sendable {
  /// Where `range` lands in `content`. A binding with no range covers the whole file.
  func place(
    _ range: ManualRange?,
    in content: ManualContent,
  ) throws(ManualRangeError) -> ManualPlacement
}

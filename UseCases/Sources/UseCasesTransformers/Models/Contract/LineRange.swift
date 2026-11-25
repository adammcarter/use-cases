/// A 1-based inclusive range of lines.
struct LineRange: Codable, Equatable, Sendable {
  /// The largest line number a document may carry: the largest integer every JSON reader keeps.
  static let largest = 9_007_199_254_740_991

  let start: Int
  let end: Int

  func contains(_ line: Int) -> Bool {
    start <= line && line <= end
  }
}

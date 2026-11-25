/// The lines of a file that a marker covers.
struct MarkedRegion: Comparable {
  let file: String
  let start: Int
  let end: Int

  /// The full id of the use case the marker names.
  let useCase: String

  var lines: String {
    start == end ? "\(start)" : "\(start)-\(end)"
  }

  static func < (
    lhs: MarkedRegion,
    rhs: MarkedRegion,
  ) -> Bool {
    if !lhs.file.isExactlyEqual(to: rhs.file) {
      return lhs.file.precedesExactly(rhs.file)
    }

    if (lhs.start, lhs.end) != (rhs.start, rhs.end) {
      return (lhs.start, lhs.end) < (rhs.start, rhs.end)
    }

    return lhs.useCase.precedesExactly(rhs.useCase)
  }

  static func == (
    lhs: MarkedRegion,
    rhs: MarkedRegion,
  ) -> Bool {
    lhs.file.isExactlyEqual(to: rhs.file) && lhs.start == rhs.start && lhs.end == rhs.end
      && lhs.useCase.isExactlyEqual(to: rhs.useCase)
  }
}

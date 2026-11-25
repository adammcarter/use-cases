extension Int64 {
  /// The sum, held at the largest or smallest value where it would go past it.
  func addingSaturated(_ other: Int64) -> Int64 {
    let (sum, overflowed) = addingReportingOverflow(other)

    guard !overflowed else {
      return other < 0 ? .min : .max
    }

    return sum
  }
}

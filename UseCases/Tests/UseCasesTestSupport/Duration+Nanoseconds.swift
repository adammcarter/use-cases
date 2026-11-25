extension Duration {
  /// The whole nanoseconds in this duration, which is as finely as the test clocks keep time. A
  /// duration beyond what that can hold, about 292 years either way, reads as the largest or
  /// smallest it can.
  var wholeNanoseconds: Int64 {
    let (seconds, attoseconds) = components
    let (scaled, scalingOverflowed) = seconds.multipliedReportingOverflow(by: 1_000_000_000)

    guard !scalingOverflowed else {
      return seconds < 0 ? .min : .max
    }

    return scaled.addingSaturated(attoseconds / 1_000_000_000)
  }
}

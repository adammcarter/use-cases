import Foundation
@testable import UseCasesCore

/// A clock that always says the same time.
struct FixedTimekeeper: Timekeeping {
  /// 2026-09-25T12:34:56.123Z, with half a millisecond to spare so no rounding can lose one.
  static let sampleDate = Date(timeIntervalSince1970: 1_790_339_696.1235)

  let date: Date

  init(date: Date = Self.sampleDate) {
    self.date = date
  }

  /// A clock at this many milliseconds since 1970.
  init(milliseconds: UInt64) {
    date = Date(timeIntervalSince1970: (Double(milliseconds) + 0.5) / 1000)
  }

  func now() -> Date {
    date
  }
}

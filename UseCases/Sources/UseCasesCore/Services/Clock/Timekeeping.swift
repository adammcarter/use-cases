import Foundation

/// Tells the time. The clock is an externality: a test passes a clock it controls, so a run id or
/// a timestamp can be known in advance.
protocol Timekeeping: Sendable {
  func now() -> Date
}

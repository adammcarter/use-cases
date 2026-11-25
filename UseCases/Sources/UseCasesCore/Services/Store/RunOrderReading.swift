import Foundation

/// Reads the allocation high-water mark (chapter 12 §9). Reading the store never needs it:
/// order is the run id. Allocation does.
protocol RunOrderReading: Sendable {
  /// The mark, or `nil` when `run-order.json` is not there, which is valid: allocation then
  /// continues above the greatest run folder. Malformed or unsupported metadata is an error, never
  /// a silent reset.
  func readRunOrder(in workspace: URL) throws(StoreProblem) -> RunOrder?
}

import Foundation

/// Cuts bytes that arrive in pieces of any size into lines, holding a line back until its newline
/// arrives.
struct LineSplitter {
  private static let newline = UInt8(ascii: "\n")

  private var pending: [UInt8] = []

  /// The lines `bytes` completes, without their newlines. A line that is not UTF-8 arrives empty.
  mutating func lines(completedBy bytes: [UInt8]) -> [String] {
    pending += bytes

    var lines: [String] = []

    while let end = pending.firstIndex(of: Self.newline) {
      lines.append(String(bytes: pending[..<end], encoding: .utf8) ?? "")
      pending.removeSubrange(...end)
    }

    return lines
  }
}

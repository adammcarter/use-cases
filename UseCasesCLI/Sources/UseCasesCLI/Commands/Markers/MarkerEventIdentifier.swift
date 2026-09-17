import Foundation

/// `generateUlid` (markers.ts, recover.ts): the time in base 32 — JavaScript's
/// `toString(32)`, so digits and A–V — upper-cased and padded to ten
/// characters, then sixteen random Crockford characters.
enum MarkerEventIdentifier {
  private static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")
  private static let radixDigits = Array("0123456789ABCDEFGHIJKLMNOPQRSTUV")

  static func generate() -> String {
    generate(now: Date())
  }

  static func generate(now: Date) -> String {
    let milliseconds = UInt64((now.timeIntervalSince1970 * 1000).rounded(.down))
    var generator = SystemRandomNumberGenerator()
    let tail = (0 ..< 16).map { _ in
      alphabet[Int.random(in: 0 ..< alphabet.count, using: &generator)]
    }
    return timePrefix(milliseconds: milliseconds) + String(tail)
  }

  /// `ms.toString(32).toUpperCase().padStart(10, "0").slice(0, 10)`.
  static func timePrefix(milliseconds: UInt64) -> String {
    var digits: [Character] = []
    var remaining = milliseconds
    repeat {
      digits.append(radixDigits[Int(remaining % 32)])
      remaining /= 32
    } while remaining > 0
    let text = String(digits.reversed())
    let padded = String(repeating: "0", count: max(0, 10 - text.count)) + text
    return String(padded.prefix(10))
  }
}

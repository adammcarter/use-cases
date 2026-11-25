/// A route fingerprint as the store keeps it: `uc-route-v<version>-<algorithm>:<value>`
/// (chapter 11). The store keeps every format it has ever been given; only equal text is the
/// same fingerprint, so a historical format the current core cannot compute is history that never
/// matches (chapter 11 §57).
struct RouteFingerprint: Hashable, Sendable, CustomStringConvertible {
  private static let prefix = "uc-route-v"
  private static let sha256Format = "uc-route-v1-sha256"
  private static let sha256DigestLength = 64

  let text: String

  /// Reads a fingerprint, refusing anything that is not a versioned representation. The
  /// `uc-route-v1-sha256` format is checked down to its 64 lowercase hex digits.
  init(validating text: String) throws(RouteFingerprintError) {
    let parts = text.splitOnScalar(":")

    guard parts.count >= 2, Self.isFormat(parts[0]) else {
      throw .notVersioned(text)
    }
    guard parts.count == 2, Self.isValue(parts[1]) else {
      throw .malformedValue(text)
    }
    if parts[0] == Self.sha256Format, !Self.isSHA256Digest(parts[1]) {
      throw .malformedValue(text)
    }

    self.text = text
  }

  var description: String {
    text
  }

  static func == (
    lhs: RouteFingerprint,
    rhs: RouteFingerprint,
  ) -> Bool {
    lhs.text.isExactlyEqual(to: rhs.text)
  }

  func hash(into hasher: inout Hasher) {
    text.hashExactly(into: &hasher)
  }

  /// `uc-route-v<version>-<algorithm>`: a version from 1 up, written without a leading zero, and
  /// an algorithm of `a-z`, `0-9` and `-`.
  private static func isFormat(_ format: String) -> Bool {
    guard format.hasPrefix(prefix) else {
      return false
    }

    let rest = Array(format.unicodeScalars.dropFirst(prefix.unicodeScalars.count))
    let version = rest.prefix {
      ("0" ... "9").contains($0)
    }
    guard let first = version.first, first != "0" else {
      return false
    }

    let algorithm = rest.dropFirst(version.count)
    guard algorithm.first == "-", algorithm.count > 1 else {
      return false
    }

    return algorithm.dropFirst().allSatisfy {
      ($0.value >= 0x61 && $0.value <= 0x7A) || ($0.value >= 0x30 && $0.value <= 0x39)
        || $0 == "-"
    }
  }

  /// One or more characters that are neither `:` nor white space as ECMA-262 `\s` has it.
  private static func isValue(_ value: String) -> Bool {
    !value.isEmpty && !value.unicodeScalars.contains {
      $0 == ":" || isECMAWhiteSpace($0)
    }
  }

  private static func isSHA256Digest(_ value: String) -> Bool {
    value.unicodeScalars.count == sha256DigestLength && value.unicodeScalars.allSatisfy {
      ($0.value >= 0x30 && $0.value <= 0x39) || ($0.value >= 0x61 && $0.value <= 0x66)
    }
  }

  private static func isECMAWhiteSpace(_ scalar: Unicode.Scalar) -> Bool {
    switch scalar.value {
    case 0x09 ... 0x0D, 0x20, 0xA0, 0x1680, 0x2000 ... 0x200A, 0x2028, 0x2029, 0x202F, 0x205F,
         0x3000, 0xFEFF:
      true
    default:
      false
    }
  }
}

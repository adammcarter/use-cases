/// Why a piece of text is not a stored route fingerprint.
enum RouteFingerprintError: Error, Equatable, Sendable {
  /// It is not `uc-route-v<version>-<algorithm>:<value>`.
  case notVersioned(String)

  /// The value after the colon is empty, holds a colon or white space, or is not the 64 lowercase
  /// hex digits of a `sha256` fingerprint.
  case malformedValue(String)
}

extension RouteFingerprintError: CustomStringConvertible {
  var description: String {
    switch self {
    case let .notVersioned(text):
      "\(AuthoredValue.quote(text)) is not a route fingerprint: it must read " +
        "'uc-route-v<version>-<algorithm>:<value>'"
    case let .malformedValue(text):
      "\(AuthoredValue.quote(text)) is not a route fingerprint: its value after the colon is " +
        "malformed"
    }
  }
}

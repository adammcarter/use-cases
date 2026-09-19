/// Small shared pieces the ledger types need when they write JSON or build
/// JavaScript-keyed sets.
extension JSONValue {
  /// A 1-based line number, or `null` when there is none.
  static func optionalNumber(_ value: Int?) -> JSONValue {
    guard let value else {
      return .null
    }
    return .number(Double(value))
  }
}

extension CodeUnitKey {
  /// A caller's string set, re-keyed by code unit.
  static func set(_ strings: Set<String>?) -> Set<CodeUnitKey>? {
    strings.map { members in
      Set(members.map(CodeUnitKey.init))
    }
  }
}

/// UTF-8 decoding the way node decodes `"utf8"` output: every ill-formed
/// sequence becomes U+FFFD and decoding carries on.
enum UTF8Text {
  static func decodeReplacingInvalid(_ bytes: [UInt8]) -> String {
    var scalars = String.UnicodeScalarView()
    var decoder = UTF8()
    var iterator = bytes.makeIterator()
    while true {
      switch decoder.decode(&iterator) {
      case let .scalarValue(scalar):
        scalars.append(scalar)
      case .error:
        scalars.append("\u{FFFD}")
      case .emptyInput:
        return String(scalars)
      }
    }
  }
}

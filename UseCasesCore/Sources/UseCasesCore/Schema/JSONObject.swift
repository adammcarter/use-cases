/// A JSON object that remembers the order its keys arrived in.
///
/// Document order is load-bearing twice over: `additionalProperties`
/// diagnostics follow the order the offending keys appear in the DATA, and the
/// canonical form the semantic hash is taken over sorts from this key list.
/// Equality deliberately IGNORES order, mirroring JavaScript deep equality.
///
/// Key IDENTITY is JavaScript's, not Swift's: two keys are the same key only
/// when their code units are identical. Swift `String` equality is canonical
/// equivalence, under which `"é"` (U+00E9) and `"e\u{301}"` are one key — so a
/// document carrying both would lose a member here while keeping it in the
/// TypeScript, and every hash over it would disagree with the ledgers already
/// written.
public struct JSONObject: Sendable, Equatable {
  public private(set) var keys: [String] = []
  private var values: [CodeUnitKey: JSONValue] = [:]

  public init() {}

  public init(_ pairs: [(String, JSONValue)]) {
    for (key, value) in pairs {
      self[key] = value
    }
  }

  public subscript(key: String) -> JSONValue? {
    get {
      values[CodeUnitKey(key)]
    }
    set {
      let identity = CodeUnitKey(key)
      guard let newValue else {
        keys.removeAll { existing in
          CodeUnitKey(existing) == identity
        }
        values[identity] = nil
        return
      }
      if values.updateValue(newValue, forKey: identity) == nil {
        keys.append(key)
      }
    }
  }

  public var count: Int {
    keys.count
  }

  public var isEmpty: Bool {
    keys.isEmpty
  }

  public func contains(_ key: String) -> Bool {
    values[CodeUnitKey(key)] != nil
  }

  /// The members, in document order.
  public var pairs: [(key: String, value: JSONValue)] {
    keys.compactMap { key in
      guard let value = values[CodeUnitKey(key)] else {
        return nil
      }
      return (key: key, value: value)
    }
  }

  public static func == (
    left: JSONObject,
    right: JSONObject,
  ) -> Bool {
    left.values == right.values
  }
}

/// A string compared and hashed by its exact UTF-8 bytes — equivalently, by its
/// UTF-16 code units — which is how JavaScript compares property names and
/// `Map`/`Set` keys. Use it wherever a Swift dictionary or set stands in for a
/// JavaScript one keyed by strings that are not constrained to ASCII.
struct CodeUnitKey: Hashable, Sendable {
  let string: String

  init(_ string: String) {
    self.string = string
  }

  static func == (
    left: CodeUnitKey,
    right: CodeUnitKey,
  ) -> Bool {
    left.string.utf8.elementsEqual(right.string.utf8)
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(string.utf8.count)
    for byte in string.utf8 {
      hasher.combine(byte)
    }
  }
}

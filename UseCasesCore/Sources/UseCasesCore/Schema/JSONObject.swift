/// A JSON object that remembers the order its keys arrived in.
///
/// Document order is load-bearing twice over: `additionalProperties`
/// diagnostics follow the order the offending keys appear in the DATA, and the
/// canonical form the semantic hash is taken over sorts from this key list.
/// Equality deliberately IGNORES order, mirroring JavaScript deep equality.
public struct JSONObject: Sendable, Equatable {
  public private(set) var keys: [String] = []
  private var values: [String: JSONValue] = [:]

  public init() {}

  public init(_ pairs: [(String, JSONValue)]) {
    for (key, value) in pairs {
      self[key] = value
    }
  }

  public subscript(key: String) -> JSONValue? {
    get { values[key] }
    set {
      guard let newValue else {
        keys.removeAll { $0 == key }
        values[key] = nil
        return
      }
      if values.updateValue(newValue, forKey: key) == nil {
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
    values[key] != nil
  }

  /// The members, in document order.
  public var pairs: [(key: String, value: JSONValue)] {
    keys.compactMap { key in
      guard let value = values[key] else {
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

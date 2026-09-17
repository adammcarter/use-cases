/// A string-keyed map with JavaScript `Map` semantics: keys compare by code
/// unit, iteration follows insertion order, re-setting a key keeps its place,
/// and deleting then setting a key moves it to the end.
struct OrderedStringMap<Value: Sendable>: Sendable {
  private var entries: [(key: String, value: Value)?] = []
  private var positions: [CodeUnitKey: Int] = [:]

  subscript(key: String) -> Value? {
    get {
      positions[CodeUnitKey(key)].flatMap { position in
        entries[position]?.value
      }
    }
    set {
      let identity = CodeUnitKey(key)
      guard let newValue else {
        if let position = positions.removeValue(forKey: identity) {
          entries[position] = nil
        }
        return
      }
      if let position = positions[identity] {
        entries[position] = (key, newValue)
      } else {
        positions[identity] = entries.count
        entries.append((key, newValue))
      }
    }
  }

  var isEmpty: Bool {
    positions.isEmpty
  }

  /// The live entries, in insertion order.
  var pairs: [(key: String, value: Value)] {
    entries.compactMap(\.self)
  }

  var keys: [String] {
    pairs.map(\.key)
  }
}

/// A string set with JavaScript `Set` semantics (see ``OrderedStringMap``).
struct OrderedStringSet: Sendable {
  private var map = OrderedStringMap<Bool>()

  init(_ members: some Sequence<String> = []) {
    for member in members {
      insert(member)
    }
  }

  mutating func insert(_ member: String) {
    map[member] = true
  }

  mutating func remove(_ member: String) {
    map[member] = nil
  }

  func contains(_ member: String) -> Bool {
    map[member] != nil
  }

  var isEmpty: Bool {
    map.isEmpty
  }

  var members: [String] {
    map.keys
  }

  /// JavaScript's default `Array.prototype.sort`: UTF-16 code-unit order,
  /// stable.
  var sortedMembers: [String] {
    JavaScriptString.sorted(members)
  }
}

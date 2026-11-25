public extension HookName {
  /// The hooks the words name, each once, in the fixed order.
  ///
  /// - Throws: ``HookNameError`` naming every word that is not a hook.
  static func named(_ words: [String]) throws(HookNameError) -> [HookName] {
    let unknown = words.filter { word in
      HookName(rawValue: word) == nil
    }

    guard unknown.isEmpty else {
      throw .unknown(names: unknown)
    }

    return allCases.filter { hook in
      words.contains(hook.rawValue)
    }
  }
}

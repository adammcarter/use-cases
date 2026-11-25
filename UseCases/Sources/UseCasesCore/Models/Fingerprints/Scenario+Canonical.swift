extension Scenario {
  /// Exactly `id`, `given`, `when` and `then`, each step list in the order written (chapter 11
  /// §89.4, §89.9). A scenario without a `given` has an empty one already.
  var canonical: CanonicalValue {
    .members([
      "id": .string(identifier.text),
      "given": .strings(given),
      "when": .strings(when),
      "then": .strings(then),
    ])
  }
}

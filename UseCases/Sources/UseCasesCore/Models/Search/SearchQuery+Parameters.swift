extension SearchQuery {
  /// The members of the parameters a `--next` token carries that say what is looked for. `search`
  /// and `docs` write the same four.
  var members: [StoreJSONMember] {
    [
      StoreJSONMember(
        key: "words",
        value: .strings(words),
      ),
      StoreJSONMember(
        key: "phrases",
        value: .array(phrases.map(StoreJSONValue.strings)),
      ),
      StoreJSONMember(
        key: "exclusions",
        value: .array(exclusions.map(StoreJSONValue.strings)),
      ),
      StoreJSONMember(
        key: "exact",
        value: .boolean(isExact),
      ),
    ]
  }

  /// Reads the members of a token's parameters, as ``members`` writes them.
  init(reading object: AuthoredObject) throws(AuthoredShapeError) {
    try self.init(
      words: object.strings("words"),
      phrases: object.lists("phrases"),
      exclusions: object.lists("exclusions"),
      isExact: object.optionalBoolean("exact") ?? false,
    )
  }
}

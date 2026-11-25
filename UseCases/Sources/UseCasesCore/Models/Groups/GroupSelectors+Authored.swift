extension GroupSelectors {
  /// Reads selectors that passed the groups schema.
  init(authored object: AuthoredObject) throws(AuthoredShapeError) {
    ids = try object.identifiers(
      GroupSelectorKind.ids.rawValue,
      parsing: Namespace.init(validating:),
    )
    prefixes = try object.identifiers(
      GroupSelectorKind.prefixes.rawValue,
      parsing: Namespace.init(validating:),
    )
    globs = try object.identifiers(
      GroupSelectorKind.globs.rawValue,
      parsing: IdentifierGlob.init(validating:),
    )
    written = Set(
      GroupSelectorKind.allCases.filter { kind in
        object.contains(kind.rawValue)
      },
    )
  }
}

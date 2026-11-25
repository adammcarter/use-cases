/// Finds the checker for each schema of the results store.
protocol StoreSchemaLoading: Sendable {
  /// - Parameters:
  ///   - schema: The schema to check against.
  ///   - unknownMembers: Whether a member the schema does not list breaks it. A reader of a
  ///     version it supports ignores them; the schema itself, as a writer obeys it, refuses them.
  func loadChecker(
    for schema: StoreSchema,
    unknownMembers: UnknownMembers,
  ) throws(StoreSchemaLoadingError) -> any SchemaChecking
}

extension StoreSchemaLoading {
  /// The checker that refuses a member the schema does not list.
  func loadChecker(for schema: StoreSchema) throws(StoreSchemaLoadingError) -> any SchemaChecking {
    try loadChecker(
      for: schema,
      unknownMembers: .refuse,
    )
  }
}

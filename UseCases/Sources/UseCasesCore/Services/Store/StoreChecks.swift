/// The schema checkers a reader runs files through.
struct StoreChecks: Sendable {
  let run: any SchemaChecking
  let result: any SchemaChecking
  let completion: any SchemaChecking

  init(
    run: any SchemaChecking,
    result: any SchemaChecking,
    completion: any SchemaChecking,
  ) {
    self.run = run
    self.result = result
    self.completion = completion
  }

  /// Checkers for the versions this core reads, which ignore a member they do not know
  /// (chapter 12 §25).
  init(loader: any StoreSchemaLoading) throws(StoreSchemaLoadingError) {
    run = try loader.loadChecker(
      for: .run,
      unknownMembers: .ignore,
    )
    result = try loader.loadChecker(
      for: .result,
      unknownMembers: .ignore,
    )
    completion = try loader.loadChecker(
      for: .completion,
      unknownMembers: .ignore,
    )
  }
}

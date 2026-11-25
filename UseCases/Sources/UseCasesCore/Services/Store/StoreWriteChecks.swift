/// The schema checkers a writer runs every file through before it writes it. A writer writes
/// exactly its version's schema (chapter 12 §25), so unlike the reader's they refuse a member
/// the schema does not list.
struct StoreWriteChecks: Sendable {
  let run: any SchemaChecking
  let result: any SchemaChecking
  let completion: any SchemaChecking
  let start: any SchemaChecking
  let runOrder: any SchemaChecking

  init(
    run: any SchemaChecking,
    result: any SchemaChecking,
    completion: any SchemaChecking,
    start: any SchemaChecking,
    runOrder: any SchemaChecking,
  ) {
    self.run = run
    self.result = result
    self.completion = completion
    self.start = start
    self.runOrder = runOrder
  }

  init(loader: any StoreSchemaLoading) throws(StoreSchemaLoadingError) {
    run = try loader.loadChecker(for: .run)
    result = try loader.loadChecker(for: .result)
    completion = try loader.loadChecker(for: .completion)
    start = try loader.loadChecker(for: .start)
    runOrder = try loader.loadChecker(for: .runOrder)
  }
}

/// Collects the problems found in one place so that a check does not hide the ones after it.
struct StoreProblemLog {
  private(set) var problems: [StoreProblem] = []

  var isClean: Bool {
    problems.isEmpty
  }

  mutating func add(_ found: [StoreProblem]) {
    problems.append(contentsOf: found)
  }

  /// Runs a check; when it finds a problem, keeps it and returns `nil`.
  mutating func attempt<Value>(_ check: () throws(StoreProblem) -> Value) -> Value? {
    do {
      return try check()
    } catch {
      problems.append(error)

      return nil
    }
  }
}

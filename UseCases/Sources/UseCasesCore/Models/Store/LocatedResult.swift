/// A result and the run it is in. Runs order by id, so the greater run id is the newer result.
struct LocatedResult: Equatable, Sendable {
  let run: RunIdentifier
  let result: StoredResult
}

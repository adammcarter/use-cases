import UseCasesCore

/// One run as the `prune` document lists it: its whole id and the size of its folder.
struct PruneRunEntry: Encodable {
  let runIdentifier: String
  let bytes: Int64

  enum CodingKeys: String, CodingKey {
    case runIdentifier = "run_id"
    case bytes
  }

  init(_ run: PrunableRun) {
    runIdentifier = run.identifier
    bytes = run.bytes
  }
}

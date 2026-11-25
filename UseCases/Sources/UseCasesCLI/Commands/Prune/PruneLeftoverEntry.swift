import UseCasesCore

/// A folder an interrupted prune left in `runs/`, as the `prune` document lists it.
struct PruneLeftoverEntry: Encodable {
  let folder: String
  let bytes: Int64

  init(_ leftover: PruneLeftover) {
    folder = leftover.location
    bytes = leftover.bytes
  }
}

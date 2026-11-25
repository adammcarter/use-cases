import UseCasesCore

/// The `store` of a `status --json` document: the store's runs, its size in bytes, and how many
/// runs `prune` would remove.
struct StatusStoreEntry: Encodable {
  let runs: Int
  let bytes: Int64
  let superseded: Int

  init(_ summary: StoreSummary) {
    runs = summary.runs
    bytes = summary.bytes
    superseded = summary.superseded
  }
}

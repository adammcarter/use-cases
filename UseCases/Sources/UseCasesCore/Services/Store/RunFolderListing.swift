/// What is in `runs/`: the run folders in ascending run id, and the entries that are not runs.
struct RunFolderListing: Equatable, Sendable {
  let identifiers: [RunIdentifier]
  let strays: [StoreProblem]
}

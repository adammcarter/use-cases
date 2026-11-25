/// A manifest diagnostic and the run it is in.
struct LocatedDiagnostic: Equatable, Sendable {
  let run: RunIdentifier
  let diagnostic: RunDiagnostic
}

@testable import UseCasesCore

/// A warner that says which use cases it was asked about, in one line.
struct MockStillMarkedWarning: StillMarkedWarning {
  func warnings(
    for identifiers: [String],
    in links: [ResolvedLink],
  ) -> [String] {
    ["marked: \(identifiers.joined(separator: ", ")) in \(links.count) links"]
  }
}

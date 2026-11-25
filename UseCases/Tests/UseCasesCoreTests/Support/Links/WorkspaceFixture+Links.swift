import Foundation
@testable import UseCasesCore

extension WorkspaceFixture {
  /// Writes the sample definition file with these bindings.
  func writeUseCase(
    bindings: [String] = [],
    routeBindings: [String] = [],
  ) throws {
    try write(
      "use-cases/toggle.yml",
      LinkSamples.definitions(
        bindings: bindings,
        routeBindings: routeBindings,
      ),
    )
  }

  /// Writes a file of bytes.
  func write(
    _ path: String,
    bytes: [UInt8],
  ) throws {
    try directory.write(
      path,
      bytes: bytes,
    )
  }

  /// The links of the loaded workspace, resolved by the real resolver.
  func resolved(using resolver: LinkResolver = LinkResolver()) throws -> LinkResolution {
    try resolver.resolveLinks(in: loaded())
  }
}

extension LinkResolution {
  /// The keys of the links, in order.
  var keys: [String] {
    links.map(\.key)
  }

  /// The problems and warnings that carry this word.
  func problems(containing word: String) -> [String] {
    problems.filter { line in
      line.contains(word)
    }
  }

  func warnings(containing word: String) -> [String] {
    warningLines.filter { line in
      line.contains(word)
    }
  }
}

extension ResolvedLink {
  /// `<file>:<start line>`.
  var place: String {
    "\(file):\(startLine)"
  }
}

extension String {
  /// The text before the first `: `, which is where a report line puts its place.
  var beforeFirstColonAndSpace: String {
    components(separatedBy: ": ").first ?? self
  }
}

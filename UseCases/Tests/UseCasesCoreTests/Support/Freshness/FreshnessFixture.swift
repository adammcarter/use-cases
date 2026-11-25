import Testing
@testable import UseCasesCore

/// A workspace on disk with the sample use case, loaded, resolved and fingerprinted by the real
/// pieces.
struct FreshnessFixture {
  let workspace: WorkspaceFixture

  init(
    root: String = FreshnessSamples.root(),
    definitions: String = FreshnessSamples.definitions(),
  ) throws {
    workspace = try WorkspaceFixture(rootConfiguration: root)
    try workspace.write("use-cases/toggle.yml", definitions)
  }

  func write(
    _ path: String,
    _ text: String = "",
  ) throws {
    try workspace.write(path, text)
  }

  /// Everything the status of the workspace would be built on.
  func fingerprints(
    using computer: RouteFingerprintComputer = RouteFingerprintComputer(),
    resolver: LinkResolver = LinkResolver(),
  ) throws -> RouteFingerprints {
    let loaded = try workspace.loaded()

    return computer.fingerprints(
      of: loaded,
      links: resolver.resolveLinks(in: loaded),
    )
  }

  /// The fingerprint of a route of the sample use case, which must exist.
  func fingerprint(
    of route: String = "unit-tests",
    using computer: RouteFingerprintComputer = RouteFingerprintComputer(),
  ) throws -> String {
    let result = try fingerprints(using: computer)

    return try #require(
      result.fingerprint(
        useCase: FreshnessSamples.useCase,
        route: route,
      ),
      "problems: \(result.problems)",
    )
  }
}

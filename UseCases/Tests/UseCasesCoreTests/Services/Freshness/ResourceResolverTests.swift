import Testing
@testable import UseCasesCore

struct ResourceResolverTests {
  private let directory: TemporaryDirectory
  private let context: DiscoveryContext
  private let resolver: ResourceResolver

  init() throws {
    directory = try TemporaryDirectory()
    context = DiscoveryContext(
      rootDirectory: directory.url,
      builtInExcludes: [],
      configuredExcludes: [],
    )
    resolver = ResourceResolver(pathFinder: ExactPathFinder(fileSystem: LocalFileSystem()))
  }

  private func resolve(
    _ resources: [RouteResource],
    among scanned: [String] = [],
  ) throws -> ResolvedResources {
    var listings = FolderListings()

    return try resolver.resolve(
      resources,
      among: scanned.map(workspacePath),
      in: context,
      listings: &listings,
    )
  }

  private func glob(_ text: String) throws -> RouteResource {
    try .glob(PathPattern(validating: text))
  }

  @Test
  func `an explicit file that is there resolves to itself`() throws {
    try directory.write("a/b.json")

    let path = try workspacePath("a/b.json")

    let resolved = try resolve([.file(path)])

    #expect(resolved.files == [path])
    #expect(resolved.problems.isEmpty)
  }

  @Test
  func `an explicit file may be one the scan would not read`() throws {
    try directory.write("vendor/a.json")

    let path = try workspacePath("vendor/a.json")

    let resolved = try resolve([.file(path)], among: [])

    #expect(resolved.files == [path])
  }

  @Test
  func `an explicit file that is not there is a problem`() throws {
    let path = try workspacePath("nope.json")

    let resolved = try resolve([.file(path)])

    #expect(resolved.files.isEmpty)
    #expect(resolved.problems == [.file(path, .missing)])
  }

  @Test
  func `an explicit path to a folder is a problem`() throws {
    try directory.makeDirectory("folder")
    let path = try workspacePath("folder")

    #expect(try resolve([.file(path)]).problems == [.content(path, .notAFile(.directory))])
  }

  @Test
  func `a glob matches among the scanned files only`() throws {
    try directory.write("fixtures/a.json")
    try directory.write("vendor/a.json")

    let resolved = try resolve(
      [glob("**/*.json")],
      among: ["fixtures/a.json"],
    )

    #expect(try resolved.files == [workspacePath("fixtures/a.json")])
  }

  @Test
  func `a glob that matches none of them is a problem`() throws {
    let pattern = try PathPattern(validating: "fixtures/*.json")

    #expect(
      try resolve([.glob(pattern)], among: ["src/a.swift"]).problems == [.matchesNothing(pattern)],
    )
  }

  @Test
  func `a glob matches files, not the folder that holds them`() throws {
    let pattern = try PathPattern(validating: "fixtures")

    #expect(
      try resolve([.glob(pattern)], among: ["fixtures/a.json"]).problems == [
        .matchesNothing(pattern),
      ],
    )
  }

  @Test
  func `two declarations reaching one file give it once`() throws {
    try directory.write("fixtures/a.json")

    let resolved = try resolve(
      [.file(workspacePath("fixtures/a.json")), glob("fixtures/*.json")],
      among: ["fixtures/a.json"],
    )

    #expect(try resolved.files == [workspacePath("fixtures/a.json")])
  }
}

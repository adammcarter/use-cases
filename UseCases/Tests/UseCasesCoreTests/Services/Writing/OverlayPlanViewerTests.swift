import Foundation
import Testing
@testable import UseCasesCore

struct OverlayPlanViewerTests {
  private let directory: TemporaryDirectory

  init() throws {
    directory = try TemporaryDirectory()
  }

  private func view(
    _ changes: [PlannedChange],
    through fileSystem: any FileSystemReading = LocalFileSystem(),
  ) throws -> WorkspaceView {
    try OverlayPlanViewer(fileSystem: fileSystem).view(
      showing: WritePlan.making(changes),
      in: directory.url,
    )
  }

  @Test
  func `a plan that makes the workspace is loaded as one, and nothing is written`() throws {
    let loaded = try view([
      .create("use-cases.yml", InitTemplates.workspace(prefix: nil)),
      .create("use-cases/example.yml", InitTemplates.example),
    ]).loader.load(from: .workspace(directory.url))

    #expect(loaded.useCases.map(\.identifier.text) == ["example.getting-started"])
    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.url.path).isEmpty)
  }

  @Test
  func `a plan that would leave the workspace invalid is loaded as invalid`() throws {
    try directory.write("use-cases.yml", InitTemplates.workspace(prefix: nil))

    let view = try view([.create(
      "use-cases/bad.yml",
      "use_cases:\n  - id: bad\n    surprise: 1\n",
    )])

    #expect(throws: WorkspaceLoadingError.self) {
      try view.loader.load(from: .workspace(directory.url))
    }
  }

  @Test
  func `links are resolved over the view, so a marker for a planned use case is found`() throws {
    try directory.write("use-cases.yml", InitTemplates.workspace(prefix: nil))
    try directory.write(
      "src/a.swift",
      "// @use-case:example.getting-started#top\nwork()\n"
        + "// @use-case:end example.getting-started#top\n",
    )
    let view = try view([.create("use-cases/example.yml", InitTemplates.example)])
    let loaded = try view.loader.load(from: .workspace(directory.url))

    let resolution = view.resolver.resolveLinks(
      in: loaded,
      including: .none,
    )

    #expect(resolution.links.count == 1)
    #expect(!resolution.isInvalid)
  }

  @Test
  func `a file to create that is there is refused, as the writer would refuse it`() throws {
    try directory.write("use-cases.yml", "mine")

    #expect(throws: PlanWritingError.exists(path: "use-cases.yml")) {
      try view([.create("use-cases.yml", "new")])
    }
  }

  @Test
  func `what discovery excludes is never read, however much of it there is`() throws {
    try directory.write(
      "use-cases.yml",
      InitTemplates.workspace(prefix: nil) + "discovery:\n  exclude:\n    - big\n",
    )
    for number in 0 ..< 20 {
      try directory.write("big/file\(number).txt", "x")
    }
    try directory.write("src/a.swift", "let a = 1")
    let logs = try TemporaryDirectory()
    let counting = try CountingFileSystem(log: logs.location(of: "reads"))

    let view = try view(
      [.create("use-cases/example.yml", InitTemplates.example)],
      through: counting,
    )
    let loaded = try view.loader.load(from: .workspace(directory.url))
    _ = view.resolver.resolveLinks(
      in: loaded,
      including: .none,
    )

    let reads = try counting.reads().keys

    #expect(!reads.contains { path in path.contains("/big/") })
    #expect(reads.contains { path in path.hasSuffix("/src/a.swift") })
  }
}

import Foundation
import Testing
import TestSupport
@testable import UseCasesCore

/// What `use-cases init` leaves behind, read as a workspace rather than as bytes.
///
/// `InitializationGoldenCorpus` pins the scaffolded bytes; these pin what those
/// bytes have to MEAN, which is what `plugin.init.vends_sample_matrix` claims:
/// the vended row shows the whole shape, and the fresh workspace loads, validates
/// and scans clean with nothing bound yet.
struct ScaffoldedWorkspaceTests {
  /// The fields the vended row documents. Each has to be introduced by a comment,
  /// or a reader copying the sample has no idea what it is for.
  static let documentedFields = [
    "value_tier",
    "journey_role",
    "usage_frequency",
    "source_refs",
    "actor",
    "intent",
    "preconditions",
    "trigger",
    "scenarios",
    "observable_outcomes",
    "verification_policy",
    "approval_policy",
  ]

  @Test(arguments: ["golden", "bad", "edge"])
  func `the vended row carries a scenario of each kind`(kind: String) throws {
    let workspace = try ScaffoldedWorkspace()

    let sample = try workspace.exampleUseCaseFile()

    let identifiers = sample.split(separator: "\n", omittingEmptySubsequences: false)
      .map { line in
        line.trimmingCharacters(in: .whitespaces)
      }
      .filter { line in
        line.hasPrefix("- id: ")
      }
      .map { line in
        String(line.dropFirst("- id: ".count))
      }
    #expect(
      identifiers.contains { identifier in
        identifier.contains(".\(kind)")
      },
      "no scenario id names a \(kind) path in \(identifiers)",
    )
  }

  @Test(arguments: documentedFields)
  func `every documented field of the vended row is introduced by a comment`(
    field: String,
  ) throws {
    let workspace = try ScaffoldedWorkspace()

    let lines = try workspace.exampleUseCaseFile().split(
      separator: "\n",
      omittingEmptySubsequences: false,
    )

    let index = try #require(
      lines.firstIndex { line in
        line.trimmingCharacters(in: .whitespaces).hasPrefix("\(field):")
      },
      "the vended row never names \(field)",
    )
    #expect(index > 0)
    let preceding = lines[max(0, index - 3) ..< index]
    #expect(
      preceding.contains { line in
        line.contains("#")
      },
      "no comment above \(field): \(preceding)",
    )
  }

  @Test
  func `the vended row tells the reader a scenario is one test`() throws {
    let workspace = try ScaffoldedWorkspace()

    let sample = try workspace.exampleUseCaseFile().lowercased()

    #expect(sample.contains("one test"))
  }

  @Test
  func `a freshly scaffolded workspace loads and validates clean`() throws {
    let workspace = try ScaffoldedWorkspace()

    let snapshot = try UseCaseMatrixLoader.load(
      context: workspace.context(),
      registry: UseCasesFixtures.registry.get(),
    )

    #expect(snapshot.validationResult()["valid"] == .bool(true))
    #expect(snapshot.validationResult()["complete"] == .bool(true))
    #expect(snapshot.addressableUseCases.isEmpty == false)
  }

  @Test
  func `a freshly scaffolded workspace scans with every row UNBOUND and nothing INVALID`() throws {
    let workspace = try ScaffoldedWorkspace()
    let context = try workspace.context()
    let options = ScanCommandOptions(
      context: context,
      productRoot: context.workspaceRoot,
      bindingsPath: NodePath.join(context.dataRoot, ".use-cases", "bindings.jsonl"),
      evidencePath: NodePath.join(context.dataRoot, ".use-cases", "proofs.jsonl"),
      policyMode: .feature,
      publicKeyResolver: { _, _ in nil },
      generatedAt: "2026-09-18T00:00:00.000Z",
    )

    let result = try ScanCommand.run(
      options,
      registry: UseCasesFixtures.registry.get(),
      runKeyLocation: RunKeyLocation(
        environment: ["UC_RUN_KEY_FILE": workspace.root + "/no-run-key/run-key"],
        homeDirectory: workspace.root + "/no-home",
      ),
    )

    #expect(result.status.rows.isEmpty == false)
    #expect(result.status.rows.allSatisfy { row in
      row.status == .unbound
    })
    #expect(result.status.summary.invalid == 0)
    #expect(result.exitCode == 0)
  }
}

/// A real repository scaffolded by `WorkspaceScaffold`, kept alive for the test.
private struct ScaffoldedWorkspace {
  let directory: TemporaryDirectory
  let root: String

  init() throws {
    directory = try TemporaryDirectory()
    root = directory.url.appendingPathComponent("demo-repo", isDirectory: true).path
    try FileManager.default.createDirectory(
      atPath: root,
      withIntermediateDirectories: true,
    )
    _ = try WorkspaceScaffold.scaffold(
      WorkspaceScaffoldOptions(repositoryRoot: root),
      git: InitializationFixtures.isolatedGit,
      clock: FixedInitializationClock(milliseconds: 0),
    )
  }

  func exampleUseCaseFile() throws -> String {
    try String(contentsOfFile: root + "/use-cases/example.yml", encoding: .utf8)
  }

  func context() throws -> ResolvedWorkspaceContext {
    try WorkspaceContextResolver.resolve(
      options: ResolveWorkspaceContextOptions(workspaceRoot: root),
      registry: UseCasesFixtures.registry.get(),
    )
  }
}

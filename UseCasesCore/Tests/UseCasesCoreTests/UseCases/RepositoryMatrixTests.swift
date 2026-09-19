import Foundation
import Testing
import TestSupport
@testable import UseCasesCore

/// This repository's own matrix — a snapshot of `use-cases/` taken by the
/// generator — loaded, and every file mutated three ways, against what the
/// TypeScript returned and wrote. A written file must hash to the TypeScript's
/// bytes exactly: any difference is churn in a user's committed matrix.
struct RepositoryMatrixTests {
  private static func tree() throws -> JSONValue {
    let files = try #require(UseCasesFixtures.repositoryMatrix.get()["files"]?.arrayValue)
    return .array(files.map { file in
      .object(JSONObject([
        ("kind", .string("file")),
        ("path", file["path"] ?? .null),
        ("text", file["text"] ?? .null),
      ]))
    })
  }

  @Test
  func `the repository matrix loads exactly as the TypeScript loaded it`() throws {
    let expected = try #require(UseCasesFixtures.repositoryMatrix.get()["load"])
    let workspace = try UseCasesFixtures.Workspace(tree: Self.tree())

    let snapshot = try UseCaseMatrixLoader.load(
      context: workspace.context(),
      registry: UseCasesFixtures.registry.get(),
    )

    #expect(!snapshot.candidates.isEmpty)
    try UseCasesFixtures.expectMembers(
      of: expected,
      equal: UseCasesFixtures.record(snapshot, probes: nil),
      in: workspace,
    )
  }

  @Test(arguments: UseCasesRepositoryMatrixCorpus.mutationCaseNames)
  func `each repository file is rewritten to TypeScript's exact bytes`(caseName: String) throws {
    let mutations = try #require(UseCasesFixtures.repositoryMatrix.get()["mutations"]?.arrayValue)
    let expected = try #require(mutations.first { mutation in
      caseName == "\(mutation["path"]?.stringValue ?? ""):\(mutation["kind"]?.stringValue ?? "")"
    })
    let workspace = try UseCasesFixtures.Workspace(tree: Self.tree())
    let options = try UseCaseMatrixMutatorTests.options(
      expected["options"],
      context: workspace.context(),
    )

    let result = try UseCaseMatrixMutator.mutate(options, registry: UseCasesFixtures.registry.get())

    #expect(UseCasesFixtures.wire(result.jsonValue) == UseCasesFixtures.wire(expected["result"]))
    let path = try workspace.absolute(UseCasesFixtures.string(expected, "path"))
    let written = try Data(contentsOf: URL(fileURLWithPath: path))
    #expect(MarkerDigest.sha256(bytes: Array(written)) == expected["written_sha256"]?.stringValue)
    if let text = expected["written_text"]?.stringValue {
      #expect(UTF8Text.decodeReplacingInvalid(Array(written)) == text)
    }
  }
}

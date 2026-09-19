import Foundation
import Testing
import TestSupport
@testable import UseCasesCore

/// Mutating real use-case files, against the TypeScript's result for the same
/// tree and options AND every file it left under `use-cases/` afterwards —
/// byte for byte, and with no temporary file left behind.
struct UseCaseMatrixMutatorTests {
  @Test(arguments: UseCasesGoldenCorpus.mutationCaseNames)
  func `a mutation returns and writes exactly what the TypeScript did`(caseName: String) throws {
    let testCase = try UseCasesFixtures.goldenCase(caseName, in: "mutation")
    let workspace = try UseCasesFixtures.Workspace(tree: testCase["tree"])
    let options = try Self.options(testCase["options"], context: workspace.context())
    let registry = try UseCasesFixtures.registry.get()

    let outcome = Result { () throws(UseCaseMatrixError) -> UseCaseMutationResult in
      try UseCaseMatrixMutator.mutate(options, registry: registry)
    }
    workspace.restoreModes()

    switch (outcome, testCase["throws"]) {
    case let (.failure(error), thrown?):
      #expect(error.code == thrown["code"]?.stringValue)
      #expect(error.message == workspace.detokenized(thrown["message"]?.stringValue ?? ""))
    case let (.success(result), nil):
      #expect(UseCasesFixtures.wire(result.jsonValue) == workspace
        .detokenized(UseCasesFixtures.wire(testCase["result"])))
    case let (.failure(error), nil):
      Issue.record("mutation threw \(error.message)")
    case let (.success(result), thrown?):
      let actual = UseCasesFixtures.wire(result.jsonValue)
      Issue.record("expected \(UseCasesFixtures.wire(thrown)), got \(actual)")
    }

    let useCasesRoot = workspace.absolute("use-cases")
    let actualFiles = FileManager.default.fileExists(atPath: useCasesRoot) ? try UseCasesFixtures
      .listTree(useCasesRoot) : []
    let expectedFiles = testCase["files_after"]?.arrayValue ?? []
    #expect(actualFiles.map(\.path) == expectedFiles.compactMap { $0["path"]?.stringValue })
    for (actual, expected) in zip(actualFiles, expectedFiles) {
      #expect(actual.text == expected["text"]?.stringValue, "file \(actual.path)")
    }
  }

  @Test
  func `the rewrite lands through a same directory temporary file named for the process`() throws {
    let testCase = try UseCasesFixtures.goldenCase(
      "upsert_into_read_only_directory_throws",
      in: "mutation",
    )
    let workspace = try UseCasesFixtures.Workspace(tree: testCase["tree"])
    let options = try Self.options(testCase["options"], context: workspace.context())

    #expect {
      try UseCaseMatrixMutator.mutate(options, registry: UseCasesFixtures.registry.get())
    } throws: { error in
      let temporaryPath = "\(workspace.absolute("use-cases/main.yml")).tmp-\(getpid())"
      let expected = "EACCES: permission denied, open '\(temporaryPath)'"
      return (error as? UseCaseMatrixError)?.message == expected
    }
  }

  static func options(
    _ value: JSONValue?,
    context: ResolvedWorkspaceContext,
  ) throws -> UseCaseMutationOptions {
    let operation = try #require(value?["operation"]?.stringValue
      .flatMap(UseCaseMutationOperation.init))
    var useCase: JSONObject?
    if let json = value?["use_case_json"]?.stringValue {
      let parsed = try JSONParser.parse(json)
      let object = try #require(parsed.objectValue)
      useCase = object
    }
    return UseCaseMutationOptions(
      context: context,
      operation: operation,
      targetFile: value?["target_file"]?.stringValue,
      useCaseIdentifier: value?["use_case_id"]?.stringValue,
      useCase: useCase,
      expectedSemanticHash: value?["expected_semantic_hash"]?.stringValue,
      reason: value?["reason"]?.stringValue,
      actor: value?["actor"]?.stringValue,
    )
  }
}

import Foundation
import Testing
import TestSupport
@testable import UseCasesCore

/// Loading `use-cases/` from real directories, against what the TypeScript
/// loader returned for the same tree: file outcomes and their order, rows in
/// walk order, addressable and ambiguous ids, every diagnostic, and the two
/// wire results.
struct UseCaseMatrixLoaderTests {
  @Test(arguments: UseCasesGoldenCorpus.loadCaseNames)
  func `a tree loads exactly as the TypeScript loaded it`(caseName: String) throws {
    let testCase = try UseCasesFixtures.goldenCase(caseName, in: "load")
    let workspace = try UseCasesFixtures.Workspace(tree: testCase["tree"])
    let registry = try UseCasesFixtures.registry.get()

    let context = try workspace.context()
    let outcome = Result { () throws(UseCaseMatrixError) -> MatrixSnapshot in
      try UseCaseMatrixLoader.load(context: context, registry: registry)
    }

    if let thrown = testCase["throws"] {
      guard case let .failure(error) = outcome else {
        Issue.record("expected the load to throw \(UseCasesFixtures.wire(thrown))")
        return
      }
      #expect(error.code == thrown["code"]?.stringValue)
      #expect(error.message == workspace.detokenized(thrown["message"]?.stringValue ?? ""))
      return
    }
    let snapshot = try outcome.get()
    try UseCasesFixtures.expectMembers(
      of: testCase["snapshot"],
      equal: UseCasesFixtures.record(snapshot, probes: testCase["probes"]),
      in: workspace,
    )
  }
}

/// Each of the three sort orders, pinned at the call site that uses it with
/// names on which the orders disagree. The expectations are the TypeScript's,
/// read from the corpus.
struct MatrixSortOrderTests {
  private func snapshot(_ caseName: String) throws -> (MatrixSnapshot, JSONValue) {
    let testCase = try UseCasesFixtures.goldenCase(caseName, in: "load")
    let workspace = try UseCasesFixtures.Workspace(tree: testCase["tree"])
    let snapshot = try UseCaseMatrixLoader.load(
      context: workspace.context(),
      registry: UseCasesFixtures.registry.get(),
    )
    return try (snapshot, #require(testCase["snapshot"]))
  }

  @Test
  func `directory entries are walked in locale order, so rows arrive in it`() throws {
    let (snapshot, expected) = try snapshot("readdir_locale_order_decides_candidate_order")

    let paths = snapshot.candidates.map(\.source.path)
    let expectedPaths = try #require(expected["candidates"]?.arrayValue)
      .compactMap { $0["source_path"]?.stringValue }
    #expect(paths == expectedPaths)
    #expect(paths.prefix(3) == ["use-cases/_x.yml", "use-cases/-x.yml", "use-cases/a_b.yml"])
  }

  @Test
  func `names locale order calls equal keep byte order`() throws {
    let (snapshot, expected) = try snapshot("ignorable_characters_tie_under_locale_order")

    let expectedPaths = try #require(expected["candidates"]?.arrayValue)
      .compactMap { $0["source_path"]?.stringValue }
    #expect(snapshot.candidates.map(\.source.path) == expectedPaths)
  }

  @Test
  func `files are reported in locale order, rejected entries among loaded ones`() throws {
    let (snapshot, expected) = try snapshot("rejected_entries_sort_among_loaded_files")

    let expectedPaths = try #require(expected["validation"]?["files"]?.arrayValue)
      .compactMap { $0["path"]?.stringValue }
    #expect(snapshot.files.map(\.path) == expectedPaths)
    #expect(snapshot.files.map(\.path) == [
      "use-cases/a.yml",
      "use-cases/m-link.yml",
      "use-cases/z.yml",
    ])
  }

  @Test
  func `an ambiguous id lists its files in code unit order, not locale order`() throws {
    let (snapshot, _) = try snapshot("ambiguous_source_paths_sort_by_code_unit")

    let group = try #require(snapshot.ambiguousUseCaseIdentifiers.first)
    #expect(group.sourcePaths == ["use-cases/B.yml", "use-cases/_c.yml", "use-cases/a.yml"])
    #expect(snapshot.diagnostics.last?.sourcePath == "use-cases/B.yml")
  }

  @Test
  func `ambiguous groups are ordered by id in locale order`() throws {
    let (snapshot, _) = try snapshot("ambiguous_groups_sort_by_locale")

    #expect(snapshot.ambiguousUseCaseIdentifiers.map(\.identifier) == [
      "x.a_b",
      "x.a-b",
      "x.a.b",
      "x.a0",
      "x.ab",
    ])
  }

  @Test
  func `addressable rows are ordered by id in locale order`() throws {
    let (snapshot, _) = try snapshot("addressable_rows_sort_by_locale")

    #expect(snapshot.addressableUseCases.map(\.identifier) == [
      "x.a_b",
      "x.a-b",
      "x.a.b",
      "x.a0",
      "x.ab",
      "x.b",
    ])
  }
}

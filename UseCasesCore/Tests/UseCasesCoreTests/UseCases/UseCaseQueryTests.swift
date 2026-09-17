import Foundation
import Testing
import TestSupport
@testable import UseCasesCore

/// Filtering addressable rows, against the ids and list result the TypeScript
/// returned for the same query over the same tree.
struct UseCaseQueryTests {
  @Test(arguments: UseCasesGoldenCorpus.queryCaseNames)
  func `a query selects exactly the rows the TypeScript selected`(caseName: String) throws {
    let section = try #require(UseCasesFixtures.golden.get()["query"])
    let testCase = try #require(section["cases"]?.arrayValue?
      .first { $0["name"]?.stringValue == caseName })
    let workspace = try UseCasesFixtures.Workspace(tree: section["tree"])
    let snapshot = try UseCaseMatrixLoader.load(
      context: workspace.context(),
      registry: UseCasesFixtures.registry.get(),
    )

    let selected = snapshot.queryUseCases(Self.query(testCase["query"]))

    let identifiers = JSONValue.array(selected.map { useCase in
      .string(useCase.identifier)
    })
    #expect(UseCasesFixtures.wire(identifiers) == UseCasesFixtures.wire(testCase["ids"]))
    let list = snapshot.listResult(for: selected)
    #expect(UseCasesFixtures.wire(list) == UseCasesFixtures.wire(testCase["list"]))
  }

  private static func query(_ value: JSONValue?) -> UseCaseQuery {
    func strings(_ key: String) -> [String] {
      (value?[key]?.arrayValue ?? []).compactMap(\.stringValue)
    }
    return UseCaseQuery(
      valueTiers: strings("valueTiers"),
      journeyRoles: strings("journeyRoles"),
      lifecycles: strings("lifecycles"),
      hostSurfaces: strings("hostSurfaces"),
      tagsAny: strings("tagsAny"),
      tagsAll: strings("tagsAll"),
      changedPaths: strings("changedPaths"),
    )
  }
}

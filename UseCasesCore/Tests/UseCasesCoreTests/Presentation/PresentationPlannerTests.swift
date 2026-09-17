import Foundation
import Testing
import TestSupport
@testable import UseCasesCore

/// Selecting a showcase or walkthrough plan, against what the TypeScript
/// returned for the same tree, rows and request: the whole result as wire
/// bytes, its schema validation, its content hash recomputed, and the card
/// rendered for every selected item — or the error it threw instead.
struct PresentationPlannerTests {
  @Test(arguments: PresentationGoldenCorpus.planCaseNames)
  func `a plan case selects exactly as the TypeScript selected it`(caseName: String) throws {
    let testCase = try PresentationFixtures.goldenCase(caseName, in: "plans")
    let run = try PresentationFixtures.run(testCase)

    if let thrown = testCase["throws"] {
      guard case let .failure(error) = run.outcome else {
        Issue.record("expected planning to throw \(PresentationFixtures.wire(thrown))")
        return
      }
      #expect(error.code == thrown["code"]?.stringValue)
      #expect(error.message == run.workspace.detokenized(thrown["message"]?.stringValue ?? ""))
      return
    }
    let result = try run.outcome.get()
    #expect(PresentationFixtures.wire(result.jsonValue) == PresentationFixtures
      .wire(testCase["result"]))
  }

  @Test(arguments: PresentationGoldenCorpus.planCaseNames)
  func `a generated plan validates against the embedded schemas as the TypeScript's did`(
    caseName: String,
  ) throws {
    let testCase = try PresentationFixtures.goldenCase(caseName, in: "plans")
    guard testCase["throws"] == nil else {
      return
    }
    let result = try PresentationFixtures.run(testCase).outcome.get()

    let resultValidation = try PresentationFixtures.validationRecord(
      "presentation-plan-result.schema.json",
      result.jsonValue,
    )
    #expect(PresentationFixtures.wire(resultValidation) == PresentationFixtures
      .wire(testCase["result_validation"]))
    if let plan = result.plan {
      let planValidation = try PresentationFixtures.validationRecord(
        "presentation-plan.schema.json",
        plan.jsonValue,
      )
      #expect(PresentationFixtures.wire(planValidation) == PresentationFixtures
        .wire(testCase["plan_validation"]))
    } else {
      #expect(testCase["plan_validation"] == .null)
    }
  }

  @Test(arguments: PresentationGoldenCorpus.planCaseNames)
  func `a generated plan's hash and cards match the TypeScript's`(caseName: String) throws {
    let testCase = try PresentationFixtures.goldenCase(caseName, in: "plans")
    guard testCase["throws"] == nil else {
      return
    }
    let result = try PresentationFixtures.run(testCase).outcome.get()

    let expectedCards = try #require(testCase["cards"]?.arrayValue)
    guard let plan = result.plan else {
      #expect(expectedCards.isEmpty)
      return
    }
    let planObject = try #require(plan.jsonValue.objectValue)
    #expect(PresentationPlanner.planContentHash(of: planObject) == testCase["plan_hash_recomputed"]?
      .stringValue)
    #expect(plan.planContentHash == testCase["plan_hash_recomputed"]?.stringValue)
    #expect(plan.selectedItems.count == expectedCards.count)
    for (item, expected) in zip(plan.selectedItems, expectedCards) {
      #expect(item.planItemIdentifier == expected["plan_item_id"]?.stringValue)
      #expect(try PresentationCardRenderer.renderCard(item) == expected["text"]?.stringValue)
    }
  }

  @Test
  func `the known timebox gap is pinned: a timebox exclusion is reported as max_items`() throws {
    let testCase = try PresentationFixtures.goldenCase("timebox_excludes_as_max_items", in: "plans")
    let plan = try #require(PresentationFixtures.run(testCase).outcome.get().plan)

    #expect(plan.selectedItems.count == 2)
    #expect(plan.exclusions.count == 4)
    #expect(plan.exclusions.allSatisfy { exclusion in
      exclusion.reasonCode == "max_items"
        && exclusion.reason == "Higher-priority items consumed the available item cap."
    })
  }

  @Test
  func `a request without generatedAt reads the injected clock once as an ISO timestamp`() throws {
    let testCase = try PresentationFixtures.goldenCase("generated_at_read_from_clock", in: "plans")
    let plan = try #require(PresentationFixtures.run(testCase).outcome.get().plan)

    #expect(plan.generatedAt == "2026-06-25T12:00:00.123Z")
    #expect(plan.planIdentifier == "plan.walkthrough.2026_06_25t12_00_00_123z")
  }
}

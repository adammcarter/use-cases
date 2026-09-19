import Foundation
import Testing
import TestSupport
@testable import UseCasesCore

/// Loading and planning capsules, against what the TypeScript's
/// `loadDemoCapsules` and `planDemoCapsule` returned or threw for the same
/// workspace.
struct DemoCapsuleLoaderTests {
  @Test(arguments: CapsulesGoldenCorpus.loadCaseNames)
  func `demo capsules load as the TypeScript loaded them`(caseName: String) throws {
    let testCase = try CapsulesFixtures.testCase(caseName, in: "load")
    let workspace = try UseCasesFixtures.Workspace(tree: testCase["tree"])
    defer {
      workspace.restoreModes()
    }
    let context = try workspace.context()
    let registry = try CapsulesFixtures.registry

    let outcome = CapsulesFixtures.outcome { () throws(DemoCapsuleError) in
      try DemoCapsuleLoader.load(context: context, registry: registry).jsonValue
    }

    CapsulesFixtures.expectSame(outcome, testCase["outcome"], in: workspace, caseName)
  }

  @Test(arguments: CapsulesGoldenCorpus.planCaseNames)
  func `a capsule is planned as the TypeScript planned it`(caseName: String) throws {
    let testCase = try CapsulesFixtures.testCase(caseName, in: "plan")
    let workspace = try UseCasesFixtures.Workspace(tree: testCase["tree"])
    let context = try workspace.context()
    let registry = try CapsulesFixtures.registry
    let capsuleIdentifier = try #require(testCase["capsule_id"]?.stringValue)

    let outcome = CapsulesFixtures.outcome { () throws(DemoCapsuleError) in
      try DemoCapsulePlanner.plan(
        context: context,
        capsuleIdentifier: capsuleIdentifier,
        registry: registry,
      ).jsonValue
    }

    CapsulesFixtures.expectSame(outcome, testCase["outcome"], in: workspace, caseName)
  }

  @Test
  func `the capsules root hangs off the data root`() throws {
    let workspace = try UseCasesFixtures.Workspace(tree: nil)

    let root = try DemoCapsuleLoader.root(context: workspace.context())

    #expect(root == workspace.path + "/demo-capsules")
  }
}

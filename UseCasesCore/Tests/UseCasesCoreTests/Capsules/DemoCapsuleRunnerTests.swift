import Foundation
import Testing
import TestSupport
@testable import UseCasesCore

/// Running capsules with real commands, against what the TypeScript's
/// `runDemoCapsule` returned or threw for the same workspace, run after run,
/// and what it left on disk.
struct DemoCapsuleRunnerTests {
  @Test(arguments: CapsulesGoldenCorpus.runCaseNames)
  func `a capsule runs as the TypeScript ran it`(caseName: String) throws {
    let testCase = try CapsulesFixtures.testCase(caseName, in: "run")
    let workspace = try UseCasesFixtures.Workspace(tree: testCase["tree"])
    defer {
      workspace.restoreModes()
    }
    let context = try workspace.context()
    let runs = try #require(testCase["runs"]?.arrayValue)

    for (index, run) in runs.enumerated() {
      for file in run["before"]?.arrayValue ?? [] {
        let path = try #require(file["path"]?.stringValue)
        let text = try #require(file["text"]?.stringValue)
        try Data(text.utf8).write(to: URL(fileURLWithPath: workspace.absolute(path)))
      }
      let runner = try Self.runner(run)
      let options = try Self.options(run["options"], context: context)

      let outcome = CapsulesFixtures.outcome { () throws(DemoCapsuleError) in
        try runner.run(options).jsonValue
      }

      CapsulesFixtures.expectSame(
        outcome,
        run["outcome"],
        in: workspace,
        "\(caseName) run \(index)",
      )
    }

    // A lone surrogate's intent digest cannot be reproduced; see the generator.
    if testCase["lone_surrogate_replaced"]?.boolValue != true {
      try CapsulesFixtures.expectSame(
        CapsulesFixtures.tree(workspace.path),
        testCase["after"],
        in: workspace,
        "\(caseName) workspace afterwards",
      )
    }
  }

  private static func runner(_ run: JSONValue) throws -> DemoCapsuleRunner {
    var environment: [String: String] = [:]
    for pair in run["environment"]?.arrayValue ?? [] {
      let members = (pair.arrayValue ?? []).compactMap(\.stringValue)
      try #require(members.count == 2)
      environment[members[0]] = members[1]
    }
    return try DemoCapsuleRunner(
      registry: CapsulesFixtures.registry,
      spawner: CapsuleProcessSpawner(),
      clock: FixedCapsuleClock(milliseconds: #require(run["clock_ms"]?.numberValue)),
      environment: environment,
    )
  }

  private static func options(
    _ value: JSONValue?,
    context: ResolvedWorkspaceContext,
  ) throws -> DemoCapsuleRunOptions {
    var options = try DemoCapsuleRunOptions(
      context: context,
      capsuleIdentifier: #require(value?["capsuleId"]?.stringValue),
      idempotencyKey: value?["idempotencyKey"]?.stringValue,
    )
    if let isExecuting = value?["executeCommands"]?.boolValue {
      options.isExecutingCommands = isExecuting
    }
    if let actor = value?["actorType"]?.stringValue {
      options.actorType = try #require(ShowcaseActorType(rawValue: actor))
    }
    if let host = value?["hostSurface"]?.stringValue {
      options.hostSurface = host
    }
    if let recordedAt = value?["recordedAt"]?.stringValue {
      options.recordedAt = recordedAt
    }
    switch value?["commandTimeoutMs"] {
    case let .number(milliseconds):
      options.commandTimeoutMilliseconds = milliseconds
    case let .string(spelled):
      options.commandTimeoutMilliseconds = try #require(Double(spelled))
    default:
      break
    }
    return options
  }
}

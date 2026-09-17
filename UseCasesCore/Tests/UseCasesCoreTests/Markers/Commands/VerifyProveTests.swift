import Foundation
import Testing
import TestSupport
@testable import UseCasesCore

/// verify and prove replayed over real workspaces with the verifier scripted,
/// each result, each runner request and every file left on disk compared as
/// bytes with what the TypeScript produced for the same steps.
struct VerifyProveTests {
  private typealias Fixtures = VerifyProveFixtures
  private typealias Scan = ScanImpactFixtures

  @Test(arguments: VerifyProveGoldenCorpus.verifyCaseNames)
  func `each verify step returns, runs and leaves on disk what the TypeScript did`(
    caseName: String,
  ) throws {
    try replay(caseName, section: "verify_cases")
  }

  @Test(arguments: VerifyProveGoldenCorpus.proveCaseNames)
  func `each prove step returns and leaves on disk what the TypeScript did`(
    caseName: String,
  ) throws {
    try replay(caseName, section: "prove_cases")
  }

  @Test
  func `every proof Swift appends verifies with the public key, in Swift and in node, and chains`(
  ) throws {
    let materialized = try Fixtures.materialized(
      "trusted_append_chains_signs_and_skips_fresh",
      in: "prove_cases",
    )
    defer {
      _ = materialized.directory
    }
    let root = materialized.root
    let context = try Fixtures.context(root: root)
    for step in materialized.steps {
      let options = try #require(step["options"])
      _ = try ProveCommand.run(
        Fixtures.proveOptions(options, context: context, root: root),
        registry: MarkerCommandsFixtures.registry.get(),
        runKeyLocation: Fixtures.runKeyLocation(options, root: root),
        environment: [:],
      )
    }
    let events = try Fixtures.proofEvents(root)
    try #require(events.count == 3, "two sweep appends and one refresh")

    let resolver = try Fixtures.publicKeyResolver()
    var crossChecks: [NodeCrossCheck.Case] = []
    for event in events {
      #expect(try ProofSignature
        .verify(event.value, resolver: resolver) == .verified(keyIdentifier: "ci-key-1"))
      let object = try #require(event.value.objectValue)
      try crossChecks.append(NodeCrossCheck.Case(
        payload: ProofSignature.signingPayload(object),
        signature: #require(event.value["signature"]?["value"]?.stringValue),
        publicKeyPEM: Fixtures.string("public_key_pem"),
        privateKeyPEM: Fixtures.string("private_key_pem"),
      ))
    }
    let chain = try EvidenceLedgerChain.verify(events)
    #expect(chain.isValid)
    #expect(chain.verifiedEntries == 3)
    for verdict in try NodeCrossCheck.run(crossChecks) {
      #expect(verdict.nodeVerifiedSwiftSignature)
    }
  }

  /// Build the case's entries under a fresh root, then run its steps in
  /// order, comparing the whole tree after every command step.
  private func replay(
    _ caseName: String,
    section: String,
  ) throws {
    let materialized = try Fixtures.materialized(caseName, in: section)
    defer {
      _ = materialized.directory
    }
    let root = materialized.root
    for (index, step) in materialized.steps.enumerated() {
      if try Scan.applyWorkspaceStep(step, root: root) {
        continue
      }
      let label = "\(caseName) step \(index)"
      let options = step["options"] ?? .object(JSONObject())
      switch step["kind"]?.stringValue {
      case "verify":
        try verifyStep(step, options: options, root: root, label: label)
      case "prove":
        try proveStep(step, options: options, root: root, label: label)
      default:
        Issue.record("\(label) has an unknown kind")
      }
      try Scan.expectSameBytes(
        Fixtures.maskedSnapshot(root),
        Fixtures.maskedWire(step["files"], root: "<ROOT>"),
        "\(label) files",
      )
    }
  }

  private func verifyStep(
    _ step: JSONValue,
    options: JSONValue,
    root: String,
    label: String,
  ) throws {
    let context = try Fixtures.context(root: root)
    let runner = ScriptedSpawnRunner(options["runner"])
    let verifyOptions = try Fixtures.verifyOptions(options, context: context, root: root)
    let registry = try MarkerCommandsFixtures.registry.get()
    let location = try Fixtures.runKeyLocation(options, root: root)
    let outcome: JSONValue
    do throws(MarkerCommandError) {
      outcome = try VerifyCommand.run(
        verifyOptions,
        registry: registry,
        spawnRunner: runner,
        runKeyLocation: location,
      ).jsonValue
    } catch {
      outcome = Scan.thrown(error)
    }
    expectOutcome(outcome, step: step, root: root, label: label)
    Scan.expectSameBytes(
      Scan.wire(.array(runner.requests.map(\.jsonValue)), root: root),
      Scan.wire(step["spawns"] ?? .array([]), root: "<ROOT>"),
      "\(label) spawns",
    )
  }

  private func proveStep(
    _ step: JSONValue,
    options: JSONValue,
    root: String,
    label: String,
  ) throws {
    let context = try Fixtures.context(root: root)
    let proveOptions = try Fixtures.proveOptions(options, context: context, root: root)
    let registry = try MarkerCommandsFixtures.registry.get()
    let location = try Fixtures.runKeyLocation(options, root: root)
    let outcome: JSONValue
    do throws(MarkerCommandError) {
      outcome = try ProveCommand.run(
        proveOptions,
        registry: registry,
        runKeyLocation: location,
        environment: Fixtures.proveEnvironment(options),
      ).jsonValue
    } catch {
      outcome = Scan.thrown(error)
    }
    expectOutcome(outcome, step: step, root: root, label: label)
  }

  /// A result against the recorded result, or a throw against the recorded
  /// throw — whichever the TypeScript produced.
  private func expectOutcome(
    _ outcome: JSONValue,
    step: JSONValue,
    root: String,
    label: String,
  ) {
    let expected = step["thrown"] ?? step["result"]
    Scan.expectSameBytes(
      Scan.wire(outcome, root: root),
      Scan.wire(expected, root: "<ROOT>"),
      "\(label) outcome",
    )
  }
}

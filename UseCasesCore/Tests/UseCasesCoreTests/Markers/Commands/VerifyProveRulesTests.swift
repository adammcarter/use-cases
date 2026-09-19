import Foundation
import Testing
import TestSupport
@testable import UseCasesCore

/// The verify and prove behaviour the corpus cannot pin byte for byte: a run
/// key minted at random, a random event id, and the real runner's output
/// feeding the recorded hashes.
struct VerifyProveRulesTests {
  private typealias Fixtures = VerifyProveFixtures

  @Test
  func `a run with records mints a missing run key and attests every record with it`(
  ) throws {
    let materialized = try Fixtures.materialized(
      "default_run_key_location",
      in: "verify_cases",
    )
    defer {
      _ = materialized.directory
    }
    let root = materialized.root
    let context = try Fixtures.context(root: root)
    var options = try Fixtures.verifyOptions(.object(JSONObject()), context: context, root: root)
    options.all = true
    options.runKeyPath = root + "/home/minted/run-key"
    let result = try VerifyCommand.run(
      options,
      registry: MarkerCommandsFixtures.registry.get(),
      spawnRunner: ScriptedSpawnRunner(nil),
      runKeyLocation: Fixtures.runKeyLocation(.object(JSONObject()), root: root),
    )

    let minted = try JavaScriptString.trim(NodeFile.readText(atPath: root + "/home/minted/run-key"))
    #expect(RunAttestation.isRunKey(minted))
    #expect(try minted != Fixtures.string("run_key"))
    let records = try #require(result.results.isEmpty ? nil : result.results)
    for record in records {
      #expect(try RunAttestation.verify(record: record.fields, key: minted))
      #expect(try !RunAttestation.verify(record: record.fields, key: Fixtures.string("run_key")))
    }
  }

  @Test
  func `the default event id is 26 random Crockford base32 characters`() {
    let alphabet = Set("0123456789ABCDEFGHJKMNPQRSTVWXYZ")
    let first = ProveCommand.generateEventIdentifier()
    let second = ProveCommand.generateEventIdentifier()
    #expect(first.count == 26)
    #expect(first.allSatisfy(alphabet.contains))
    #expect(first != second)
  }

  @Test
  func `invalid UTF-8 output is hashed as the decoded text re-encoded, not as its bytes`(
  ) throws {
    let materialized = try Fixtures.materialized(
      "default_run_key_location",
      in: "verify_cases",
    )
    defer {
      _ = materialized.directory
    }
    let root = materialized.root
    let context = try Fixtures.context(root: root)
    var options = try Fixtures.verifyOptions(.object(JSONObject()), context: context, root: root)
    options.all = true
    let result = try VerifyCommand.run(
      options,
      registry: MarkerCommandsFixtures.registry.get(),
      spawnRunner: ShellRedirect(script: #"printf 'ok\377'; printf '\342\202' >&2"#),
      runKeyLocation: Fixtures.runKeyLocation(.object(JSONObject()), root: root),
    )

    let record = try #require(result.results.first)
    #expect(record.status == .pass)
    #expect(record.standardOutputSHA256 == MarkerDigest.sha256(bytes: [
      0x6F,
      0x6B,
      0xEF,
      0xBF,
      0xBD,
    ]))
    #expect(record.standardErrorSHA256 == MarkerDigest.sha256(bytes: [0xEF, 0xBF, 0xBD]))
  }

  @Test
  func `a verifier node refuses to start stops verify with its refusal, writing nothing`() throws {
    let materialized = try Fixtures.materialized("default_run_key_location", in: "verify_cases")
    defer {
      _ = materialized.directory
    }
    let root = materialized.root
    let context = try Fixtures.context(root: root)
    var options = try Fixtures.verifyOptions(.object(JSONObject()), context: context, root: root)
    options.all = true
    options.outPath = root + "/workspace/.use-cases/verification-results.jsonl"
    let registry = try MarkerCommandsFixtures.registry.get()
    let location = try Fixtures.runKeyLocation(.object(JSONObject()), root: root)

    #expect(throws: MarkerCommandError.verifierSpawn(.commandMissing)) {
      try VerifyCommand.run(
        options,
        registry: registry,
        spawnRunner: RefusingRunner(),
        runKeyLocation: location,
      )
    }
    #expect(!FileManager.default.fileExists(atPath: options.outPath ?? ""))
  }

  @Test
  func `a signing key that is not an ed25519 PEM stops prove before anything is appended`() throws {
    let materialized = try Fixtures.materialized(
      "producer_defaults_without_authority",
      in: "prove_cases",
    )
    defer {
      _ = materialized.directory
    }
    let root = materialized.root
    let context = try Fixtures.context(root: root)
    let step = try #require(materialized.steps.first?["options"])
    var options = try Fixtures.proveOptions(step, context: context, root: root)
    options.signingKey = ProveSigningKey(privateKeyPEM: "not a key", keyIdentifier: "ci-key-1")
    let registry = try MarkerCommandsFixtures.registry.get()
    let location = try Fixtures.runKeyLocation(step, root: root)

    #expect(throws: MarkerCommandError.proofSignature(.invalidPrivateKey)) {
      try ProveCommand.run(options, registry: registry, runKeyLocation: location, environment: [:])
    }
    #expect(try Fixtures.proofEvents(root).isEmpty)
  }
}

/// A runner that refuses every request as node refuses a missing command.
private struct RefusingRunner: VerifySpawnRunning {
  func run(_: VerifySpawnRequest) throws(VerifySpawnError) -> VerifySpawnResult {
    throw .commandMissing
  }
}

/// The real runner, with whatever verifier a row resolved to replaced by one
/// `/bin/sh` one-liner — so a test never runs a row's own command.
private struct ShellRedirect: VerifySpawnRunning {
  let script: String

  func run(_ request: VerifySpawnRequest) throws(VerifySpawnError) -> VerifySpawnResult {
    try VerifyProcessRunner().run(VerifySpawnRequest(
      command: ["/bin/sh", "-c", script],
      workingDirectory: request.workingDirectory,
      timeoutSeconds: request.timeoutSeconds,
    ))
  }
}

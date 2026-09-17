import Foundation
import Testing
import TestSupport
@testable import UseCasesCore

/// Every showcase run, token, request, floor and binding case the TypeScript
/// oracle recorded, replayed through the Swift port and compared as wire bytes:
/// results, thrown codes and messages, and every ledger file left behind.
struct ShowcaseRunCorpusTests {
  @Test(arguments: ShowcaseGoldenCorpus.runCaseNames)
  func `a run's steps return, throw and write exactly what the TypeScript did`(
    caseName: String,
  ) throws {
    let testCase = try ShowcaseFixtures.goldenCase(caseName, in: "runs")
    let workspace = try ShowcaseFixtures.workspace()
    let context = try workspace.context()
    for file in testCase["plan_files"]?.arrayValue ?? [] {
      let path = try UseCasesFixtures.string(file, "path")
      try ShowcaseFixtures.appendRaw(
        UseCasesFixtures.string(file, "text"),
        toPath: workspace.absolute(path),
      )
    }

    for (index, step) in try #require(testCase["steps"]?.arrayValue).enumerated() {
      let label = "step \(index) \(step["op"]?.stringValue ?? "")"
      let outcome = try ShowcaseFixtures.run(
        step,
        plans: testCase["plans"],
        workspace: workspace,
        context: context,
      )
      switch (outcome, step["throws"]) {
      case let (.failure(error), .some(expected)):
        ShowcaseFixtures.expectThrown(error, equals: expected, in: workspace)
      case let (.success(value), .none):
        ShowcaseFixtures.expectSameWire(
          ShowcaseFixtures.wire(value),
          workspace.detokenized(ShowcaseFixtures.wire(step["result"])),
          label,
        )
      case let (.failure(error), .none):
        Issue.record("\(label) threw \(error.code): \(error.message)")
      case let (.success(value), .some(expected)):
        let returned = ShowcaseFixtures.wire(value).prefix(200)
        Issue.record("\(label) returned \(returned), expected \(ShowcaseFixtures.wire(expected))")
      }
    }

    let files = try FileManager.default.fileExists(atPath: workspace.absolute("showcase-runs"))
      ? UseCasesFixtures.listTree(workspace.absolute("showcase-runs")) : []
    let expectedFiles = try #require(testCase["files_after"]?.arrayValue)
    #expect(files.map(\.path) == expectedFiles.compactMap { $0["path"]?.stringValue })
    for (actual, expected) in zip(files, expectedFiles) {
      ShowcaseFixtures.expectSameWire(
        actual.text ?? "<directory>",
        expected["text"]?.stringValue ?? "<directory>",
        "bytes of \(actual.path)",
      )
    }
  }
}

struct ApprovalTokenCorpusTests {
  @Test(arguments: ShowcaseGoldenCorpus.verifyCaseNames)
  func `a token verifies or fails exactly as the TypeScript's verifyApprovalToken did`(
    caseName: String,
  ) throws {
    let testCase = try ShowcaseFixtures.goldenCase(caseName, in: "verify")
    let result = try Self.verification(testCase)
    ShowcaseFixtures.expectSameWire(
      ShowcaseFixtures.wire(result.jsonValue),
      ShowcaseFixtures.wire(testCase["result"]),
      caseName,
    )
  }

  @Test(arguments: ["webauthn_secp256k1_es256", "webauthn_ed448_eddsa"])
  func `a credential key type swift-crypto cannot verify is refused where node accepts it`(
    caseName: String,
  ) throws {
    let testCase = try ShowcaseFixtures.goldenCase(caseName, in: "divergences")
    #expect(testCase["result"]?["ok"] == .bool(true), "node verified this assertion")
    let result = try Self.verification(testCase)
    let credential = testCase["args"]?["credentials"]?.objectValue?.keys.first ?? ""
    #expect(result == .failed(
      code: .webAuthnBadSignature,
      message: "webauthn signature for credential_id \(credential) did not verify",
    ))
  }

  static func verification(_ testCase: JSONValue) throws -> ApprovalTokenVerification {
    let arguments = try #require(testCase["args"])
    var resolvers = try ShowcaseFixtures.resolvers(arguments)
    if let credentials = arguments["credentials"] {
      resolvers = ShowcaseTrustResolvers(
        publicKeyResolver: resolvers.publicKeyResolver,
        tierResolver: resolvers.tierResolver,
        webAuthnCredentialResolver: ShowcaseFixtures.credentialResolver(credentials),
      )
    }
    let burned = Set(arguments["burned"]?.arrayValue?.compactMap(\.stringValue) ?? [])
    return try ApprovalTokenVerifier.verify(
      ApprovalTokenVerificationOptions(
        token: arguments["token"],
        resolvers: resolvers,
        liveBinding: #require(arguments["live_binding"]),
        isNonceBurned: { jti in
          burned.contains(jti)
        },
        nowMilliseconds: arguments["now_ms"]?.numberValue,
        assuranceFloor: #require(AssuranceTier(rawValue: UseCasesFixtures.string(
          arguments,
          "assurance_floor",
        ))),
      ),
      clock: ShowcaseFixtures.FixedClock(milliseconds: #require(testCase["clock_ms"]?.numberValue)),
    )
  }

  @Test(arguments: ShowcaseGoldenCorpus.requestCaseNames)
  func `a request or token is minted, signed or built exactly as the TypeScript did`(
    caseName: String,
  ) throws {
    let testCase = try ShowcaseFixtures.goldenCase(caseName, in: "requests")
    let arguments = try #require(testCase["args"])
    switch try (Self.requestOutcome(testCase), testCase["throws"]) {
    case let (.failure(error), .some(expected)):
      ShowcaseFixtures.expectThrown(error, equals: expected, in: nil)
    case let (.success(value), .none):
      guard testCase["op"] == .string("sign") else {
        #expect(ShowcaseFixtures.wire(.object(value)) == ShowcaseFixtures.wire(testCase["result"]))
        return
      }
      // node's ed25519 signatures are deterministic and swift-crypto's are
      // randomised, so the value differs byte for byte; everything else must
      // match, and the Swift signature must verify under the same key.
      let expected = try #require(testCase["result"]?.objectValue)
      #expect(Self.withoutSignatureValue(value) == Self.withoutSignatureValue(expected))
      let keyName = try UseCasesFixtures.string(arguments, "key")
      let publicKey = try #require(ShowcaseFixtures.section("keys")[keyName]?["public_pem"]?
        .stringValue)
      let keyIdentifier = try UseCasesFixtures.string(arguments, "key_id")
      let verified = try ProofSignature.verify(.object(value)) { identifier, _ in
        identifier == keyIdentifier ? publicKey : nil
      }
      #expect(verified == .verified(keyIdentifier: keyIdentifier))
    default:
      Issue.record("\(caseName): outcome kind differs from the TypeScript's")
    }
  }

  /// The recorded mint, sign or build call, made through the Swift port.
  private static func requestOutcome(_ testCase: JSONValue) throws
    -> Result<JSONObject, ShowcaseError>
  {
    let arguments = try #require(testCase["args"])
    let tokens = try ApprovalTokens(
      clock: ShowcaseFixtures.FixedClock(milliseconds: #require(testCase["clock_ms"]?.numberValue)),
      uuidSource: ShowcaseFixtures.FixedUUIDSource(uuid: UseCasesFixtures.string(testCase, "uuid")),
    )
    do {
      switch try UseCasesFixtures.string(testCase, "op") {
      case "mint":
        return try .success(tokens.mintRequest(
          binding: #require(arguments["binding"]?.objectValue),
          nowMilliseconds: arguments["now_ms"]?.numberValue,
          ttlMinutes: arguments["ttl_minutes"]?.numberValue,
          jti: arguments["jti"]?.stringValue,
        ))
      case "sign":
        return try .success(ApprovalTokens.sign(
          request: #require(arguments["request"]?.objectValue),
          decision: UseCasesFixtures.string(arguments, "decision"),
          privateKeyPEM: ShowcaseFixtures.privateKeyPEM(UseCasesFixtures.string(arguments, "key")),
          keyIdentifier: UseCasesFixtures.string(arguments, "key_id"),
          assuranceMethod: arguments["assurance_method"]?.stringValue,
        ))
      default:
        return try .success(ApprovalTokens.buildWebAuthnToken(
          request: #require(arguments["request"]?.objectValue),
          decision: UseCasesFixtures.string(arguments, "decision"),
          assertion: #require(arguments["assertion"]?.objectValue),
        ))
      }
    } catch let error as ShowcaseError {
      return .failure(error)
    }
  }

  private static func withoutSignatureValue(_ token: JSONObject) -> String {
    var stripped = token
    var signature = token["signature"]?.objectValue ?? JSONObject()
    signature["value"] = nil
    stripped["signature"] = .object(signature)
    return ShowcaseFixtures.wire(.object(stripped))
  }

  @Test
  func `a plan's approval floor is the TypeScript's for every recorded plan`() throws {
    for (index, testCase) in try #require(ShowcaseFixtures.section("floors").arrayValue)
      .enumerated()
    {
      let floor = try ApprovalPolicy.assuranceFloor(forPlan: testCase["plan"])
      #expect(floor.rawValue == testCase["floor"]?.stringValue, "floor case \(index)")
    }
  }

  @Test(arguments: ShowcaseGoldenCorpus.bindingCaseNames)
  func `an approval binding is computed from events exactly as the TypeScript did`(
    caseName: String,
  ) throws {
    let testCase = try ShowcaseFixtures.goldenCase(caseName, in: "bindings")
    let events = try #require(testCase["events"]?.arrayValue)
    do throws(ShowcaseError) {
      let binding = try ApprovalBinding.binding(runIdentifier: "run.binding", events: events)
      #expect(testCase["throws"] == nil)
      #expect(ShowcaseFixtures.wire(.object(binding)) == ShowcaseFixtures.wire(testCase["result"]))
    } catch {
      let expected = try #require(testCase["throws"])
      ShowcaseFixtures.expectThrown(error, equals: expected, in: nil)
    }
  }
}

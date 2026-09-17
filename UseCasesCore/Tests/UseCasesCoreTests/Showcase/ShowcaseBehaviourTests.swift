import Crypto
import Foundation
import Testing
import TestSupport
@testable import UseCasesCore

/// The showcase behaviours the brief names, each pinned on its own beside the
/// corpus.
struct ShowcaseBehaviourTests {
  private static let recordedAt = "2026-06-25T12:00:00.000Z"

  private static func recording(
    _ context: ResolvedWorkspaceContext,
    key: String,
    actor: ShowcaseActorType = .agent,
  ) -> ShowcaseRecording {
    ShowcaseRecording(
      context: context,
      actorType: actor,
      hostSurface: "codex.cli",
      idempotencyKey: key,
      recordedAt: recordedAt,
    )
  }

  private static func startedRun(_ workspace: UseCasesFixtures.Workspace) throws -> (
    context: ResolvedWorkspaceContext,
    runIdentifier: String,
  ) {
    let context = try workspace.context()
    let testCase = try ShowcaseFixtures.goldenCase(
      "verdicts_failure_decisions_and_the_finish_gate",
      in: "runs",
    )
    let plan = try #require(testCase["plans"]?["two"]?.objectValue)
    let started = try ShowcaseRecorder().start(
      plan: plan,
      controlMode: .agentLed,
      recording: recording(context, key: "behaviour"),
    )
    return try (context, #require(started.event["run_id"]?.stringValue))
  }

  private static func ledgerText(
    _ context: ResolvedWorkspaceContext,
    _ runIdentifier: String,
  ) throws -> String {
    try String(
      contentsOfFile: ShowcaseLedger.ledgerPath(context: context, runIdentifier: runIdentifier),
      encoding: .utf8,
    )
  }

  @Test
  func `a secret in an observation never reaches the ledger file`() throws {
    let workspace = try ShowcaseFixtures.workspace()
    let (context, runIdentifier) = try Self.startedRun(workspace)

    let result = try ShowcaseRecorder().recordObservation(
      runIdentifier: runIdentifier,
      planItemIdentifier: "item.showcase.live.golden",
      text: "Logged in with password=hunter2hunter2 using ghp_abcdefghijklmnopqrstuvwxyz0123.",
      recording: Self.recording(context, key: "secret"),
    )

    let text = try Self.ledgerText(context, runIdentifier)
    let holdsPassword = text.contains("hunter2")
    let holdsToken = text.contains("abcdefghijklmnopqrstuvwxyz0123")
    let holdsPlaceholder = text.contains("password=[redacted]")
    #expect(!holdsPassword)
    #expect(!holdsToken)
    #expect(holdsPlaceholder)
    #expect(result.event["payload"]?["observation"]?.stringValue?.contains("hunter2") == false)
  }

  @Test
  func `a secret in a failure decision reason is stored as given, as the TypeScript stores it`(
  ) throws {
    let workspace = try ShowcaseFixtures.workspace()
    let (context, runIdentifier) = try Self.startedRun(workspace)
    let recorder = ShowcaseRecorder()
    let observation = try recorder.recordObservation(
      runIdentifier: runIdentifier,
      planItemIdentifier: "item.showcase.live.golden",
      text: "Seen.",
      recording: Self.recording(context, key: "o"),
    )
    let verdict = try recorder.recordVerdict(
      runIdentifier: runIdentifier,
      planItemIdentifier: "item.showcase.live.golden",
      verdict: .fail,
      observationEventIdentifiers: [#require(observation.event["event_id"]?.stringValue)],
      recording: Self.recording(context, key: "v"),
    )

    _ = try recorder.recordFailureDecision(
      runIdentifier: runIdentifier,
      verdictEventIdentifier: #require(verdict.event["event_id"]?.stringValue),
      decision: .continue,
      reason: "Flaky, password=hunter2hunter2.",
      recording: Self.recording(context, key: "d"),
    )

    let holdsReason = try Self.ledgerText(context, runIdentifier)
      .contains("password=hunter2hunter2")
    #expect(holdsReason)
  }

  /// The owner-recorded race (docs/rewrite/ladder-notes.md): appends to one
  /// run take no lock, so writers that read the same ledger write the same
  /// sequence and event id. Measured on this port with 8 writers: duplicates
  /// in 30 rounds of 30 run alone. A loaded machine can serialise the writers
  /// by accident, so up to 20 rounds are tried before the pin fails.
  @Test
  func `concurrent appends to one run can write the same sequence and event id`() async throws {
    var duplicatedRound: (sequences: [Double], identifiers: [String])?
    for _ in 0 ..< 20 where duplicatedRound == nil {
      let workspace = try ShowcaseFixtures.workspace()
      let (context, runIdentifier) = try Self.startedRun(workspace)
      await withTaskGroup(of: Void.self) { group in
        for writer in 0 ..< 8 {
          group.addTask {
            _ = try? ShowcaseRecorder().recordObservation(
              runIdentifier: runIdentifier,
              planItemIdentifier: "item.showcase.live.golden",
              text: "Writer \(writer).",
              recording: Self.recording(context, key: "writer-\(writer)"),
            )
          }
        }
      }
      let events = try ShowcaseLedger.read(context: context, runIdentifier: runIdentifier).events
      let sequences = events.compactMap { $0["sequence"]?.numberValue }
      let identifiers = events.compactMap { $0["event_id"]?.stringValue }
      if Set(sequences).count < sequences.count {
        duplicatedRound = (sequences, identifiers)
      }
    }

    let round = try #require(duplicatedRound, "no round of 20 wrote a duplicate sequence")
    #expect(Set(round.identifiers).count < round.identifiers.count)
    for (sequence, identifier) in zip(round.sequences, round.identifiers) {
      #expect(identifier.hasSuffix(".\(Int(sequence))"))
    }
  }

  /// A WebAuthn assertion signed here, with the P-256 key the corpus pins as
  /// `credential-es256` (the generator's constant seed), verifies through the
  /// full token check. Such a token, exported once, also verified in node's
  /// `verifyApprovalToken` (and failed there once its client data changed).
  @Test
  func `a P-256 assertion signed by swift-crypto verifies against the pinned credential`() throws {
    let seed = Array(SHA256.hash(data: Data("showcase-corpus webauthn p256 credential".utf8)))
    let privateKey = try P256.Signing.PrivateKey(rawRepresentation: seed)
    let binding = JSONObject([
      ("run_id", .string("run.alpha")),
      ("finish_event_id", .string("evt.7")),
    ])
    let clientData = Array(JSONWriter.encode(.object(JSONObject([
      ("type", .string("webauthn.get")),
      ("challenge", .string(WebAuthnAssertion.challenge(for: .object(binding)))),
      ("origin", .string("https://localhost")),
    ]))).utf8)
    let authenticatorData = Array(SHA256.hash(data: Data("localhost".utf8))) + [0x05, 0, 0, 0, 1]
    let signatureBase = authenticatorData + Array(SHA256.hash(data: clientData))
    let signature = try Array(privateKey.signature(for: signatureBase).derRepresentation)
    let request = try ApprovalTokens(clock: ShowcaseFixtures
      .FixedClock(milliseconds: 1_782_388_800_000))
      .mintRequest(binding: binding, ttlMinutes: 60, jti: "approval.swift-signed")
    let token = ApprovalTokens.buildWebAuthnToken(
      request: request,
      decision: "approved",
      assertion: JSONObject([
        ("credential_id", .string("credential-es256")),
        ("authenticator_data", .string(WebAuthnAssertion.base64URL(authenticatorData))),
        ("client_data_json", .string(WebAuthnAssertion.base64URL(clientData))),
        ("signature", .string(WebAuthnAssertion.base64URL(signature))),
      ]),
    )
    let spki = try #require(ShowcaseFixtures.section("ec_keys")["p256"]?["spki"]?.stringValue)
    #expect(WebAuthnAssertion.base64URL(Array(privateKey.publicKey.derRepresentation)) == spki)

    let result = try ApprovalTokenVerifier.verify(
      ApprovalTokenVerificationOptions(
        token: .object(token),
        resolvers: ShowcaseTrustResolvers(keyring: ShowcaseFixtures.keyring("main")),
        liveBinding: .object(binding),
        isNonceBurned: { _ in false },
        nowMilliseconds: 1_782_388_800_000,
        assuranceFloor: .webAuthnHardware,
      ),
    )

    #expect(result == .verified(
      jti: "approval.swift-signed",
      decision: "approved",
      keyIdentifier: "credential-es256",
      assuranceTier: .webAuthnHardware,
    ))
  }
}

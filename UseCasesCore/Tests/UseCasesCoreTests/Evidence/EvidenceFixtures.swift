import Foundation
import Testing
import TestSupport
@testable import UseCasesCore

/// Access to the generated TypeScript evidence corpus, and the records the
/// generator wrote, rebuilt from Swift values so the two compare as wire JSON.
///
/// Trees are rebuilt with ``UseCasesFixtures/Workspace``, which the matrix tests
/// already use: the corpus spells trees the same way.
enum EvidenceFixtures {
  static let golden: Result<JSONValue, SchemaError> = {
    do throws(SchemaError) {
      return try .success(JSONParser.parse(EvidenceGoldenCorpus.json))
    } catch {
      return .failure(error)
    }
  }()

  /// The corpus section `section`, whole.
  static func section(_ section: String) throws -> JSONValue {
    try #require(golden.get()[section], "corpus has no section \(section)")
  }

  /// The case called `name` in the corpus section `section`.
  static func goldenCase(
    _ name: String,
    in section: String,
  ) throws -> JSONValue {
    let cases = try #require(Self.section(section).arrayValue, "section \(section) is not a list")
    let match = cases.first { $0["name"]?.stringValue == name }
    return try #require(match, "corpus section \(section) has no case \(name)")
  }

  static func wire(_ value: JSONValue?) -> String {
    UseCasesFixtures.wire(value)
  }

  // MARK: - Records

  /// `readEvidenceLedgers`' result, as the generator recorded it.
  static func readRecord(_ result: EvidenceLedgerReadResult) -> JSONValue {
    .object(JSONObject([
      ("ledgers", .array(result.ledgers.map(\.jsonValue))),
      ("events", .array(result.events.map(\.jsonValue))),
      ("diagnostics", .array(result.diagnostics.map(\.jsonValue))),
    ]))
  }

  /// The generator's `snapshotRecord`: the wire status result, then the
  /// snapshot's own members under their TypeScript names.
  static func snapshotRecord(_ snapshot: EvidenceSnapshot) -> JSONValue {
    .object(JSONObject([
      ("status_result", snapshot.statusResult()),
      ("complete", .bool(snapshot.isComplete)),
      ("integrity", .object(JSONObject([
        ("state", .string(snapshot.integrity.state.rawValue)),
        ("unknownScopeDamage", .bool(snapshot.integrity.hasUnknownScopeDamage)),
        ("invalidAggregateCount", .number(Double(snapshot.integrity.invalidAggregateCount))),
        ("tornTailCount", .number(Double(snapshot.integrity.tornTailCount))),
      ]))),
      ("ledgers", .array(snapshot.ledgers.map(\.jsonValue))),
      ("aggregates", .array(snapshot.aggregates.map(aggregateRecord))),
      ("diagnostics", .array(snapshot.diagnostics.map(\.jsonValue))),
      ("counts", snapshot.counts.jsonValue),
      ("events", .array(snapshot.events.map(\.jsonValue))),
    ]))
  }

  /// `EvidenceAggregateState` as `JSON.stringify` spells the TypeScript object:
  /// camelCase members, and an `undefined` member left out.
  static func aggregateRecord(_ aggregate: EvidenceAggregateState) -> JSONValue {
    var object = JSONObject()
    object["evidenceId"] = .string(aggregate.evidenceIdentifier)
    object["status"] = .string(aggregate.status.rawValue)
    object["effectiveObservation"] = aggregate.effectiveObservation.map(JSONValue.object)
    object["targetLinks"] = .array(aggregate.targetLinks)
    object["assurance"] = .object(aggregate.assurance)
    object["freshnessInputs"] = .object(aggregate.freshnessInputs)
    object["eventIds"] = .array(aggregate.eventIdentifiers.map(JSONValue.string))
    object["replacementEvidenceId"] = aggregate.replacementEvidenceIdentifier
    return .object(object)
  }

  /// A thrown error as the generator recorded it: its `code` and `message`.
  static func expectThrown(
    _ error: EvidenceEventError,
    equals expected: JSONValue,
    in workspace: UseCasesFixtures.Workspace,
    sourceLocation: SourceLocation = #_sourceLocation,
  ) {
    let expectedCode = expected["code"]?.stringValue
    let expectedMessage = workspace.detokenized(expected["message"]?.stringValue ?? "")
    #expect(error.code == (expectedCode ?? error.code), sourceLocation: sourceLocation)
    #expect(error.message == expectedMessage, sourceLocation: sourceLocation)
  }

  /// `JSON.parse`'s own wording is accepted as differing (see
  /// docs/rewrite/ladder-notes.md, row 4): an `evidence_parse_error` keeps its
  /// code, path and position, and its message is masked — unless it is the
  /// duplicate-key message, which is this port's own and compared exactly.
  static func maskingParserWording(_ value: JSONValue) -> JSONValue {
    switch value {
    case let .array(items):
      return .array(items.map(maskingParserWording))
    case let .object(object):
      var masked = JSONObject()
      for member in object.pairs {
        masked[member.key] = maskingParserWording(member.value)
      }
      if masked["code"] == .string("evidence_parse_error"),
         masked["message"] != .string(EvidenceLedgerReader.duplicateKeysMessage)
      {
        masked["message"] = .string("<JSON.parse wording>")
      }
      return .object(masked)
    default:
      return value
    }
  }

  /// Compare every member of an expected record against the actual one, member
  /// by member so a failure names the part that differs.
  static func expectMembers(
    of expected: JSONValue?,
    equal actual: JSONValue,
    in workspace: UseCasesFixtures.Workspace,
    sourceLocation: SourceLocation = #_sourceLocation,
  ) throws {
    let expectedObject = try #require(expected?.objectValue, sourceLocation: sourceLocation)
    for member in expectedObject.pairs {
      let expectedText = workspace.detokenized(wire(maskingParserWording(member.value)))
      let actualText = wire(actual[member.key].map(maskingParserWording))
      #expect(actualText == expectedText, "member \(member.key)", sourceLocation: sourceLocation)
    }
  }

  // MARK: - Injected externalities

  /// A clock that never moves: every `Date.now()` answers the same instant.
  struct FixedClock: EvidenceClock {
    let milliseconds: Double

    func now() async -> Double {
      milliseconds
    }

    func sleep(milliseconds _: Int) async {}
  }

  /// A clock that moves only when the lock waits, by exactly the wait asked
  /// for, and counts the waits. The lock's timeout runs in microseconds.
  actor SteppedClock: EvidenceClock {
    private(set) var milliseconds: Double
    private(set) var sleeps = 0

    init(milliseconds: Double) {
      self.milliseconds = milliseconds
    }

    func now() async -> Double {
      milliseconds
    }

    func sleep(milliseconds duration: Int) async {
      milliseconds += Double(duration)
      sleeps += 1
    }
  }

  /// The same bytes on every draw.
  struct FixedRandomSource: EvidenceRandomSource {
    let bytes: [UInt8]

    init(hexadecimal: String) {
      var bytes: [UInt8] = []
      var index = hexadecimal.startIndex
      while index < hexadecimal.endIndex {
        let next = hexadecimal.index(index, offsetBy: 2)
        bytes.append(UInt8(hexadecimal[index ..< next], radix: 16) ?? 0)
        index = next
      }
      self.bytes = bytes
    }

    func bytes(count: Int) -> [UInt8] {
      #expect(count == bytes.count, "random source asked for \(count) bytes")
      return bytes
    }
  }

  // MARK: - Options from the corpus

  static func appendOptions(
    _ options: JSONValue,
    context: ResolvedWorkspaceContext,
  ) throws -> EvidenceAppendOptions {
    let target = try #require(options["target"])
    let method = options["method"].map { method in
      EvidenceObservationMethod(
        type: EvidenceMethodType(rawValue: method["type"]?.stringValue ?? "") ?? .reported,
        executable: method["executable"]?.stringValue,
        argv: method["argv"]?.arrayValue?.compactMap(\.stringValue),
      )
    }
    return try EvidenceAppendOptions(
      context: context,
      idempotencyKey: string(options, "idempotencyKey"),
      target: EvidenceTarget(
        useCaseIdentifier: string(target, "use_case_id"),
        scenarioIdentifier: target["scenario_id"]?.stringValue,
        useCaseSemanticHash: string(target, "use_case_semantic_hash"),
      ),
      kind: string(options, "kind"),
      result: string(options, "result"),
      summary: string(options, "summary"),
      actorType: #require(EvidenceActorType(rawValue: string(options, "actorType"))),
      hostSurface: string(options, "hostSurface"),
      method: method,
    )
  }

  static func voidOptions(
    _ options: JSONValue,
    context: ResolvedWorkspaceContext,
  ) throws -> EvidenceVoidOptions {
    try EvidenceVoidOptions(
      context: context,
      evidenceIdentifier: string(options, "evidenceId"),
      expectedHeadEventIdentifier: string(options, "expectedHeadEventId"),
      reason: string(options, "reason"),
      idempotencyKey: string(options, "idempotencyKey"),
      actorType: #require(EvidenceActorType(rawValue: string(options, "actorType"))),
      hostSurface: string(options, "hostSurface"),
    )
  }

  static func string(
    _ value: JSONValue,
    _ key: String,
  ) throws -> String {
    try #require(value[key]?.stringValue, "missing string \(key)")
  }
}

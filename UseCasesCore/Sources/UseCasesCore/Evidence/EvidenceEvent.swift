/// Who recorded an event.
public enum EvidenceActorType: String, CaseIterable, Sendable {
  case user
  case agent
  case script
  case system
}

/// How an observation was captured.
public enum EvidenceMethodType: String, CaseIterable, Sendable {
  case reported
  case observed
  case structuredCommand = "structured_command"
}

/// The use case (and optionally scenario) a piece of evidence is about.
public struct EvidenceTarget: Sendable, Equatable {
  public let useCaseIdentifier: String
  public let scenarioIdentifier: String?
  public let useCaseSemanticHash: String

  public init(
    useCaseIdentifier: String,
    scenarioIdentifier: String?,
    useCaseSemanticHash: String,
  ) {
    self.useCaseIdentifier = useCaseIdentifier
    self.scenarioIdentifier = scenarioIdentifier
    self.useCaseSemanticHash = useCaseSemanticHash
  }

  /// `{ use_case_id, scenario_id?, use_case_semantic_hash }`, `scenario_id`
  /// left out when absent as `JSON.stringify` leaves out `undefined`.
  var jsonValue: JSONValue {
    var object = JSONObject([("use_case_id", .string(useCaseIdentifier))])
    object["scenario_id"] = scenarioIdentifier.map(JSONValue.string)
    object["use_case_semantic_hash"] = .string(useCaseSemanticHash)
    return .object(object)
  }
}

/// The capture method a caller supplies for a performed run.
public struct EvidenceObservationMethod: Sendable, Equatable {
  public let type: EvidenceMethodType
  public let executable: String?
  public let argv: [String]?

  public init(
    type: EvidenceMethodType,
    executable: String? = nil,
    argv: [String]? = nil,
  ) {
    self.type = type
    self.executable = executable
    self.argv = argv
  }

  /// `{ type, executable?, argv? }`.
  var jsonValue: JSONValue {
    var object = JSONObject([("type", .string(type.rawValue))])
    object["executable"] = executable.map(JSONValue.string)
    object["argv"] = argv.map { values in
      .array(values.map(JSONValue.string))
    }
    return .object(object)
  }
}

/// One ledger line that passed the event shape check: an object whose
/// `event_type`, `event_id` and `aggregate_id` are strings and whose `sequence`
/// is a number. Nothing else about it is checked, so every other member is
/// read as the JSON it is.
public struct EvidenceEvent: Sendable, Equatable {
  /// The whole event, members in JavaScript property order.
  public let object: JSONObject
  public let eventType: String
  public let eventIdentifier: String
  public let aggregateIdentifier: String
  public let sequence: Double

  /// An event the append path built, its shape members given directly.
  init(
    object: JSONObject,
    eventType: String,
    eventIdentifier: String,
    aggregateIdentifier: String,
    sequence: Double,
  ) {
    self.object = object
    self.eventType = eventType
    self.eventIdentifier = eventIdentifier
    self.aggregateIdentifier = aggregateIdentifier
    self.sequence = sequence
  }

  /// `isEvidenceEventShape`, or nil.
  init?(shape value: JSONValue) {
    guard let object = value.objectValue,
          let eventType = object["event_type"]?.stringValue,
          let eventIdentifier = object["event_id"]?.stringValue,
          let aggregateIdentifier = object["aggregate_id"]?.stringValue,
          let sequence = object["sequence"]?.numberValue
    else {
      return nil
    }
    self.init(
      object: object,
      eventType: eventType,
      eventIdentifier: eventIdentifier,
      aggregateIdentifier: aggregateIdentifier,
      sequence: sequence,
    )
  }

  /// A member, or nil where JavaScript reads `undefined`.
  public subscript(key: String) -> JSONValue? {
    object[key]
  }

  public var jsonValue: JSONValue {
    .object(object)
  }
}

/// What reading one ledger file found.
public struct EvidenceLedgerResult: Sendable, Equatable {
  /// Relative to the data root, `/`-separated.
  public let path: String
  public let isComplete: Bool
  public let eventsLoaded: Int
  public let hasTornTail: Bool
  public let hasUnknownScopeDamage: Bool

  /// `{ path, complete, events_loaded, torn_tail, unknown_scope_damage }`.
  public var jsonValue: JSONValue {
    .object(JSONObject([
      ("path", .string(path)),
      ("complete", .bool(isComplete)),
      ("events_loaded", .number(Double(eventsLoaded))),
      ("torn_tail", .bool(hasTornTail)),
      ("unknown_scope_damage", .bool(hasUnknownScopeDamage)),
    ]))
  }
}

/// `readEvidenceLedgers`' result.
public struct EvidenceLedgerReadResult: Sendable, Equatable {
  public let ledgers: [EvidenceLedgerResult]
  public let events: [EvidenceEvent]
  public let diagnostics: [Diagnostic]
}

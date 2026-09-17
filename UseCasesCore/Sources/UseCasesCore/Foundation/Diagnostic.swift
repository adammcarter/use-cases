/// The severity a ``Diagnostic`` declares.
public enum DiagnosticSeverity: String, Codable, Sendable, CaseIterable {
  case info
  case warning
  case error
}

/// A one-based line and column inside a source file.
public struct SourcePosition: Codable, Sendable, Equatable {
  public let line: Int
  public let column: Int

  public init(
    line: Int,
    column: Int,
  ) {
    self.line = line
    self.column = column
  }
}

/// The span a diagnostic refers to inside its source file.
public struct SourceSpan: Codable, Sendable, Equatable {
  public let start: SourcePosition
  public let end: SourcePosition

  public init(
    start: SourcePosition,
    end: SourcePosition,
  ) {
    self.start = start
    self.end = end
  }
}

/// A single machine-readable problem reported against workspace data.
///
/// The wire shape is frozen contract: `source_path`, `json_pointer` and
/// `entity_id` are always present and may be null, while `source_span` is
/// omitted entirely when absent.
public struct Diagnostic: Codable, Sendable, Equatable {
  public let code: String
  public let severity: DiagnosticSeverity
  public let message: String
  public let sourcePath: String?
  public let jsonPointer: String?
  public let sourceSpan: SourceSpan?
  public let entityIdentifier: String?
  public let relatedIdentifiers: [String]

  enum CodingKeys: String, CodingKey {
    case code
    case severity
    case message
    case sourcePath = "source_path"
    case jsonPointer = "json_pointer"
    case sourceSpan = "source_span"
    case entityIdentifier = "entity_id"
    case relatedIdentifiers = "related_ids"
  }

  public init(
    code: String,
    severity: DiagnosticSeverity = .error,
    message: String,
    sourcePath: String? = nil,
    jsonPointer: String? = nil,
    sourceSpan: SourceSpan? = nil,
    entityIdentifier: String? = nil,
    relatedIdentifiers: [String] = [],
  ) {
    self.code = code
    self.severity = severity
    self.message = message
    self.sourcePath = sourcePath
    self.jsonPointer = jsonPointer
    self.sourceSpan = sourceSpan
    self.entityIdentifier = entityIdentifier
    self.relatedIdentifiers = relatedIdentifiers
  }

  /// Encoding is explicit because the wire contract and Swift's synthesised
  /// encoder disagree: the synthesised one drops every nil optional, but
  /// `source_path`, `json_pointer` and `entity_id` must survive AS null, while
  /// `source_span` must vanish when absent.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)

    try container.encode(code, forKey: .code)
    try container.encode(severity, forKey: .severity)
    try container.encode(message, forKey: .message)

    try container.encode(sourcePath, forKey: .sourcePath)
    try container.encode(jsonPointer, forKey: .jsonPointer)
    try container.encodeIfPresent(sourceSpan, forKey: .sourceSpan)
    try container.encode(entityIdentifier, forKey: .entityIdentifier)

    try container.encode(relatedIdentifiers, forKey: .relatedIdentifiers)
  }
}

/// The outcome of validating a document: whether it passed, and what was found.
public struct ValidationResult: Sendable, Equatable {
  public let isValid: Bool
  public let diagnostics: [Diagnostic]

  public init(
    isValid: Bool,
    diagnostics: [Diagnostic],
  ) {
    self.isValid = isValid
    self.diagnostics = diagnostics
  }
}

/// How usable a loaded matrix is: nothing blocking, blocked but with rows to
/// address, or blocked with none.
public enum MatrixIntegrityState: String, Sendable, Equatable {
  case clean
  case partial
  case unusable
}

/// What happened to one file under `use-cases/`. The raw values are frozen
/// wire contract (`matrix-validation-result.schema.json`).
public enum MatrixFileStatus: String, Sendable, Equatable, CaseIterable {
  case loaded
  case parseError = "parse_error"
  case schemaError = "schema_error"
  case unknownVersion = "unknown_version"
  case duplicateIdentifier = "duplicate_id"
  case brokenReference = "broken_reference"
  case ambiguousReference = "ambiguous_reference"
  case pathEscape = "path_escape"
  case symlinkRejected = "symlink_rejected"
  case inputOutputError = "io_error"
  case resourceLimitExceeded = "resource_limit_exceeded"
}

/// Where a loaded row came from.
public struct UseCaseSource: Sendable, Equatable {
  /// The file, relative to the data root, with `/` separators.
  public let path: String

  /// `/use_cases/<index>` inside that file.
  public let jsonPointer: String

  /// `sha256:<hex>` over the file's bytes.
  public let fileByteHash: String

  public init(
    path: String,
    jsonPointer: String,
    fileByteHash: String,
  ) {
    self.path = path
    self.jsonPointer = jsonPointer
    self.fileByteHash = fileByteHash
  }
}

/// One use-case row, as read from a schema-valid file.
public struct LoadedUseCase: Sendable, Equatable {
  /// The row exactly as the file spells it.
  public let value: JSONObject

  /// The `feature` block of the file the row sits in.
  public let feature: JSONObject

  /// The row's semantic hash.
  public let semanticHash: String

  public let source: UseCaseSource

  public init(
    value: JSONObject,
    feature: JSONObject,
    semanticHash: String,
    source: UseCaseSource,
  ) {
    self.value = value
    self.feature = feature
    self.semanticHash = semanticHash
    self.source = source
  }

  /// The row's `id`. The schema requires one, so the empty fallback is never
  /// seen for a row that loaded.
  public var identifier: String {
    value["id"]?.stringValue ?? ""
  }
}

/// One file's outcome.
public struct MatrixFileResult: Sendable, Equatable {
  public let path: String
  public let status: MatrixFileStatus

  /// Present once the file parsed.
  public let semanticHash: String?

  /// Present once the file was read.
  public let fileHash: String?

  public init(
    path: String,
    status: MatrixFileStatus,
    semanticHash: String? = nil,
    fileHash: String? = nil,
  ) {
    self.path = path
    self.status = status
    self.semanticHash = semanticHash
    self.fileHash = fileHash
  }
}

/// A use-case id declared by more than one row.
public struct AmbiguousIdentifierGroup: Sendable, Equatable {
  public let identifier: String

  /// Every file declaring it — once per row, so a file declaring it twice is
  /// listed twice — in UTF-16 code-unit order.
  public let sourcePaths: [String]

  public init(
    identifier: String,
    sourcePaths: [String],
  ) {
    self.identifier = identifier
    self.sourcePaths = sourcePaths
  }
}

/// The structural tallies a matrix validation reports.
public struct MatrixStructuralCounts: Sendable, Equatable {
  public let filesDiscovered: Int
  public let filesLoaded: Int
  public let filesExcluded: Int
  public let useCaseCandidates: Int
  public let useCasesAddressable: Int
  public let useCasesAmbiguous: Int
  public let useCasesStructurallyClean: Int
  public let brokenReferences: Int
}

/// The matrix's overall health.
public struct MatrixIntegrity: Sendable, Equatable {
  public let state: MatrixIntegrityState

  /// True when at least one row was read, addressable or not.
  public let isPopulated: Bool

  /// Error-severity diagnostics, the count that decides ``state``.
  public let blockingDiagnosticCount: Int
}

/// Looking a use case up by id.
public enum UseCaseResolution: Sendable, Equatable {
  case resolved(identifier: String, useCase: LoadedUseCase)
  case missing(identifier: String)
  case ambiguous(identifier: String, candidates: [LoadedUseCase])

  /// `resolved`, `missing` or `ambiguous`, as the TypeScript's `kind`.
  public var kind: String {
    switch self {
    case .resolved: "resolved"
    case .missing: "missing"
    case .ambiguous: "ambiguous"
    }
  }
}

/// Looking a scenario up inside a use case.
public enum ScenarioResolution: Sendable, Equatable {
  case resolved(useCaseIdentifier: String, scenarioIdentifier: String, useCase: LoadedUseCase)
  case missing(useCaseIdentifier: String, scenarioIdentifier: String)
  case ambiguous(useCaseIdentifier: String, scenarioIdentifier: String, candidates: [LoadedUseCase])

  public var kind: String {
    switch self {
    case .resolved: "resolved"
    case .missing: "missing"
    case .ambiguous: "ambiguous"
    }
  }
}

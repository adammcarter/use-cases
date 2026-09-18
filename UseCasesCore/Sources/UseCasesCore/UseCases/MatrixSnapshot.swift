/// Everything one load of `use-cases/` found: every file's outcome, every row,
/// the rows that can be addressed by id, and why the rest cannot.
///
/// This is the port of `buildMatrixSnapshot` in
/// `packages/core/src/useCases/integrity.ts`. Three orders are in play and
/// each is the TypeScript's own: ambiguous groups, addressable rows and files
/// sort by `localeCompare`; the source paths INSIDE a group sort by a bare
/// `.sort()`, which is UTF-16 code-unit order; `candidates` keep the order the
/// directory walk found them in.
public struct MatrixSnapshot: Sendable {
  public let context: ResolvedWorkspaceContext

  /// True when no diagnostic is an error.
  public let isComplete: Bool

  public let integrity: MatrixIntegrity

  /// Every file's outcome, by path in `localeCompare` order.
  public let files: [MatrixFileResult]

  /// Every row read, in directory-walk order.
  public let candidates: [LoadedUseCase]

  /// The rows whose id is unique, by id in `localeCompare` order.
  public let addressableUseCases: [LoadedUseCase]

  /// The ids declared more than once, by id in `localeCompare` order.
  public let ambiguousUseCaseIdentifiers: [AmbiguousIdentifierGroup]

  /// The context's diagnostics, then the load's, then duplicate ids, then
  /// broken and ambiguous references.
  public let diagnostics: [Diagnostic]

  public let counts: MatrixStructuralCounts

  public let approvalTrust: WorkspaceApprovalTrust?

  /// Rows by id. Keyed by code unit because lookups take caller-supplied ids,
  /// which the id pattern does not constrain.
  private let rowsByIdentifier: [CodeUnitKey: [LoadedUseCase]]

  //: @use-case:matrix.product.integrity_degraded_nonfatal
  /// Assemble a snapshot from what a load found.
  public init(
    context: ResolvedWorkspaceContext,
    files: [MatrixFileResult],
    candidates: [LoadedUseCase],
    diagnostics loadDiagnostics: [Diagnostic],
  ) {
    let grouping = RowGrouping(candidates)
    let ambiguous = grouping.ambiguousGroups()
    let ambiguousIdentifiers = Set(ambiguous.map { group in
      CodeUnitKey(group.identifier)
    })
    let addressable = candidates
      .filter { candidate in
        !ambiguousIdentifiers.contains(CodeUnitKey(candidate.identifier))
      }
      .sorted { left, right in
        JavaScriptStringOrder.localeAscending(left.identifier, right.identifier)
      }
    let references = grouping.referenceProblems(of: addressable)
    let diagnostics = context.diagnostics + loadDiagnostics
      + ambiguous.map(Self.duplicateDiagnostic)
      + references.diagnostics

    let blocking = diagnostics.count { diagnostic in
      diagnostic.severity == .error
    }
    self.context = context
    isComplete = blocking == 0
    integrity = MatrixIntegrity(
      state: blocking == 0 ? .clean : (addressable.isEmpty ? .unusable : .partial),
      isPopulated: !candidates.isEmpty,
      blockingDiagnosticCount: blocking,
    )
    self.files = files.sorted { left, right in
      JavaScriptStringOrder.localeAscending(left.path, right.path)
    }
    self.candidates = candidates
    addressableUseCases = addressable
    ambiguousUseCaseIdentifiers = ambiguous
    self.diagnostics = diagnostics
    counts = Self.structuralCounts(
      files: files,
      candidates: candidates,
      addressable: addressable,
      ambiguousIdentifiers: ambiguousIdentifiers,
      references: references,
    )
    approvalTrust = context.approvalTrust
    rowsByIdentifier = grouping.rowsByIdentifier
  }

  //: @use-case:end matrix.product.integrity_degraded_nonfatal

  /// The row with `identifier`, or why there is not exactly one.
  public func resolveUseCase(_ identifier: String) -> UseCaseResolution {
    guard let rows = rowsByIdentifier[CodeUnitKey(identifier)], let first = rows.first else {
      return .missing(identifier: identifier)
    }
    if rows.count > 1 {
      return .ambiguous(identifier: identifier, candidates: rows)
    }
    return .resolved(identifier: identifier, useCase: first)
  }

  /// The scenario `scenarioIdentifier` inside use case `useCaseIdentifier`.
  public func resolveScenario(
    useCaseIdentifier: String,
    scenarioIdentifier: String,
  ) -> ScenarioResolution {
    let useCase: LoadedUseCase
    switch resolveUseCase(useCaseIdentifier) {
    case let .resolved(_, resolved):
      useCase = resolved
    case let .ambiguous(_, candidates):
      return .ambiguous(
        useCaseIdentifier: useCaseIdentifier,
        scenarioIdentifier: scenarioIdentifier,
        candidates: candidates,
      )
    case .missing:
      return .missing(useCaseIdentifier: useCaseIdentifier, scenarioIdentifier: scenarioIdentifier)
    }
    let matches = (useCase.value["scenarios"]?.arrayValue ?? []).count { scenario in
      guard let identifier = scenario["id"]?.stringValue else {
        return false
      }
      return identifier.utf16.elementsEqual(scenarioIdentifier.utf16)
    }
    if matches == 0 {
      return .missing(useCaseIdentifier: useCaseIdentifier, scenarioIdentifier: scenarioIdentifier)
    }
    if matches > 1 {
      return .ambiguous(
        useCaseIdentifier: useCaseIdentifier,
        scenarioIdentifier: scenarioIdentifier,
        candidates: [useCase],
      )
    }
    return .resolved(
      useCaseIdentifier: useCaseIdentifier,
      scenarioIdentifier: scenarioIdentifier,
      useCase: useCase,
    )
  }

  private static func structuralCounts(
    files: [MatrixFileResult],
    candidates: [LoadedUseCase],
    addressable: [LoadedUseCase],
    ambiguousIdentifiers: Set<CodeUnitKey>,
    references: ReferenceProblems,
  ) -> MatrixStructuralCounts {
    MatrixStructuralCounts(
      filesDiscovered: files.count,
      filesLoaded: files.count { file in
        file.status == .loaded
      },
      filesExcluded: files.count { file in
        file.status != .loaded
      },
      useCaseCandidates: candidates.count,
      useCasesAddressable: addressable.count,
      useCasesAmbiguous: candidates.count { candidate in
        ambiguousIdentifiers.contains(CodeUnitKey(candidate.identifier))
      },
      useCasesStructurallyClean: addressable.count { useCase in
        !references.brokenSources.contains(CodeUnitKey(useCase.identifier))
      },
      brokenReferences: references.diagnostics.count,
    )
  }

  private static func duplicateDiagnostic(_ group: AmbiguousIdentifierGroup) -> Diagnostic {
    Diagnostic(
      code: "duplicate_id",
      message: "Use case '\(group.identifier)' appears in multiple files.",
      sourcePath: group.sourcePaths.first,
      entityIdentifier: group.identifier,
      relatedIdentifiers: group.sourcePaths,
    )
  }
}

/// The broken and ambiguous references found, one diagnostic each, and the
/// rows that made them.
private struct ReferenceProblems {
  let diagnostics: [Diagnostic]
  let brokenSources: Set<CodeUnitKey>
}

/// `groupByUseCaseId`: rows by id, in the order each id was first met — a
/// JavaScript `Map`'s insertion order.
private struct RowGrouping {
  private(set) var rowsByIdentifier: [CodeUnitKey: [LoadedUseCase]] = [:]
  private var identifiersInOrder: [String] = []

  init(_ candidates: [LoadedUseCase]) {
    for candidate in candidates {
      let key = CodeUnitKey(candidate.identifier)
      if rowsByIdentifier[key] == nil {
        identifiersInOrder.append(candidate.identifier)
      }
      rowsByIdentifier[key, default: []].append(candidate)
    }
  }

  /// Every id held by more than one row. The groups sort by `localeCompare`;
  /// the paths inside each sort by a bare `.sort()`, UTF-16 code-unit order.
  func ambiguousGroups() -> [AmbiguousIdentifierGroup] {
    identifiersInOrder
      .compactMap { identifier -> AmbiguousIdentifierGroup? in
        guard let rows = rowsByIdentifier[CodeUnitKey(identifier)], rows.count > 1 else {
          return nil
        }
        let paths = rows.map(\.source.path).sorted(by: JavaScriptStringOrder.codeUnitAscending)
        return AmbiguousIdentifierGroup(identifier: identifier, sourcePaths: paths)
      }
      .sorted { left, right in
        JavaScriptStringOrder.localeAscending(left.identifier, right.identifier)
      }
  }

  /// Every `related_use_cases` entry of an addressable row that names no row,
  /// or more than one.
  func referenceProblems(
    of addressable: [LoadedUseCase],
  ) -> ReferenceProblems {
    var diagnostics: [Diagnostic] = []
    var brokenSources = Set<CodeUnitKey>()
    for useCase in addressable {
      let targets = (useCase.value["related_use_cases"]?.arrayValue ?? []).compactMap(\.stringValue)
      for target in targets {
        let rows = rowsByIdentifier[CodeUnitKey(target)]
        guard rows == nil || (rows?.count ?? 0) > 1 else {
          continue
        }
        brokenSources.insert(CodeUnitKey(useCase.identifier))
        diagnostics.append(Self.referenceDiagnostic(
          isMissing: rows == nil,
          useCase: useCase,
          target: target,
        ))
      }
    }
    return ReferenceProblems(diagnostics: diagnostics, brokenSources: brokenSources)
  }

  private static func referenceDiagnostic(
    isMissing: Bool,
    useCase: LoadedUseCase,
    target: String,
  ) -> Diagnostic {
    let kind = isMissing ? "missing" : "ambiguous"
    return Diagnostic(
      code: isMissing ? "broken_reference" : "ambiguous_reference",
      message: "Use case '\(useCase.identifier)' references \(kind) use case '\(target)'.",
      sourcePath: useCase.source.path,
      jsonPointer: "\(useCase.source.jsonPointer)/related_use_cases",
      entityIdentifier: useCase.identifier,
      relatedIdentifiers: [target],
    )
  }
}

import Foundation

/// Judges a workspace from its current fingerprints and the sealed runs of its results store
/// (chapter 12 §36): each route is verified, failed, error, incomplete, unverified or stale, and
/// each use case takes the worst of its gating routes.
public struct StatusJudge: StatusJudging {
  private let fingerprinter: any RouteFingerprintComputing
  private let reading: Result<any StoreReading, StoreSchemaLoadingError>
  let promiseFingerprinter: any PromiseFingerprinting
  private let measurer: any StoreMeasuring

  /// A judge over the real file system and the bundled store schemas.
  public init() {
    self.init(
      fingerprinter: RouteFingerprintComputer(),
      reading: Result { () throws(StoreSchemaLoadingError) -> any StoreReading in
        try StoreReader()
      },
      promiseFingerprinter: PromiseFingerprinter(),
      measurer: StoreMeasurer(),
    )
  }

  init(
    fingerprinter: any RouteFingerprintComputing,
    reading: Result<any StoreReading, StoreSchemaLoadingError>,
    promiseFingerprinter: any PromiseFingerprinting,
    measurer: any StoreMeasuring = StoreMeasurer(),
  ) {
    self.fingerprinter = fingerprinter
    self.reading = reading
    self.promiseFingerprinter = promiseFingerprinter
    self.measurer = measurer
  }

  public func judge(
    _ workspace: LoadedWorkspace,
    links: LinkResolution,
  ) throws(StatusJudgingError) -> WorkspaceStatus {
    try judge(
      workspace,
      links: links,
      measuringStore: false,
    )
  }

  public func judge(
    _ workspace: LoadedWorkspace,
    links: LinkResolution,
    measuringStore: Bool,
  ) throws(StatusJudgingError) -> WorkspaceStatus {
    let fingerprints = fingerprinter.fingerprints(
      of: workspace,
      links: links,
    )

    guard !fingerprints.isInvalid else {
      throw .invalidWorkspace(problems: fingerprints.problems)
    }

    let history = try readHistory(in: workspace)
    let judging = StatusInputs(
      workspace: workspace,
      links: links,
      fingerprints: fingerprints,
      history: history,
    )

    var statuses: [UseCaseStatus] = []

    for useCase in workspace.useCases {
      try statuses.append(status(of: useCase, using: judging))
    }

    return WorkspaceStatus(
      useCases: statuses.sorted(by: Self.precedes),
      warnings: warnings(using: judging),
      hasSealedRuns: !history.runs.isEmpty,
      signOffRequired: workspace.scopes.first?.configuration.rootSettings?.signOff == .required,
      hasRunCommand: Self.hasRunCommand(in: workspace),
      store: measuringStore
        ? summary(
          of: history,
          at: fingerprints,
          in: workspace,
        ) : nil,
    )
  }

  /// The store's line of chapter 16 §9: `nil` when it holds no run.
  private func summary(
    of history: StoreHistory,
    at fingerprints: RouteFingerprints,
    in workspace: LoadedWorkspace,
  ) -> StoreSummary? {
    let runs = history.runs.count + history.unfinishedRuns.count

    guard runs > 0 else {
      return nil
    }

    return StoreSummary(
      runs: runs,
      bytes: measurer.bytes(
        below: workspace.root.appendingPathComponent(StoreLayout.storeFolder),
      ),
      superseded: history.supersededRuns(
        keeping: history.runsInUse(at: fingerprints.current),
      ).count,
    )
  }

  private func readHistory(in workspace: LoadedWorkspace) throws(StatusJudgingError)
    -> StoreHistory
  {
    let reader: any StoreReading

    switch reading {
    case let .success(found):
      reader = found
    case let .failure(error):
      throw .storage(problems: ["the store's schemas could not be loaded: \(error)"])
    }

    do {
      return try reader.readHistory(in: workspace.root)
    } catch {
      switch error {
      case let .damaged(problems):
        throw .storage(problems: problems.map(\.description))
      }
    }
  }

  /// Worst first, drafts after every verification state, then by id (chapter 16 §9).
  private static func precedes(
    _ lhs: UseCaseStatus,
    _ rhs: UseCaseStatus,
  ) -> Bool {
    if lhs.status.reportRank != rhs.status.reportRank {
      return lhs.status.reportRank < rhs.status.reportRank
    }

    return lhs.identifier.precedesExactly(rhs.identifier)
  }
}

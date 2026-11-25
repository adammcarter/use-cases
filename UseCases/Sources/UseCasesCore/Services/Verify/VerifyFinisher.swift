import Foundation

/// Finishes the runs `verify --start` opened.
public struct VerifyFinisher: VerifyFinishing {
  /// What there is to say when no validation is set up (chapter 13 §13).
  static let nothingToRead =
    "no validations set up in use-cases-bridge.yml, so nothing to read; "
      + "record verdicts with `use-cases record`"

  private let store: Result<VerifyStore, StoreSchemaLoadingError>
  private let finishPoint: Result<any FinishPointing, StoreSchemaLoadingError>

  /// A finisher over the real file system and the system clock, running bundled transformers
  /// beside the running `use-cases`, with SIGINT and SIGTERM stopping a transformer that runs.
  /// The signals are taken over only while a transformer runs, and are given back when it ends.
  public init() {
    self.init(scope: SignalCancellationScope())
  }

  /// A finisher that asks the observer `cancellation` makes whether the request was cancelled,
  /// taking over no signal. The observer is made when the first transformer is about to run.
  ///
  /// - Parameter cancellation: Makes the observer a running transformer is stopped by.
  public init(cancellation: @escaping @Sendable () -> any CancellationObserving) {
    self.init(scope: ObservedCancellationScope(makeObserver: cancellation))
  }

  private init(scope: any CancellationScoping) {
    let clock = SystemTimekeeper()
    let store = Result { () throws(StoreSchemaLoadingError) in
      try VerifyStore(clock: clock)
    }

    self.init(
      store: store,
      finishPoint: store.map { store -> any FinishPointing in
        FinishPoint(
          store: store,
          sources: SourceReader(access: store.access),
          judge: RouteJudge(),
          digester: ValidationsDigester(),
          fingerprinter: RouteFingerprintComputer(),
          makeRunner: { cancellation in
            TransformerRunner.production(cancellation: cancellation)
          },
          cancellation: scope,
          clock: clock,
        )
      },
    )
  }

  init(
    store: Result<VerifyStore, StoreSchemaLoadingError>,
    finishPoint: Result<any FinishPointing, StoreSchemaLoadingError>,
  ) {
    self.store = store
    self.finishPoint = finishPoint
  }

  public func finish(
    _ request: VerifyFinishRequest,
    in resolved: ResolvedWorkspace,
    reloading: any WorkspaceReloading,
  ) async throws(VerifyError) -> VerifiedRun {
    let workspace = resolved.workspace
    let store = try store.opened()
    let chosen = try await chosen(
      by: request,
      in: workspace,
      store: store,
    )

    guard let run = chosen else {
      return VerifiedRun(nothingToReadNotes: [Self.nothingToRead])
    }

    let finishing = try finishPoint.opened()
    let folder = store.folder(
      of: run.identifier,
      in: workspace.root,
    )

    let outcome: Result<VerifiedRun, VerifyError>?

    do {
      outcome = try await store.locks.holding(run: folder.url) {
        await finish(
          run,
          in: resolved,
          reloading: reloading,
          through: finishing,
          store: store,
        )
      }
    } catch {
      throw .storage(error.description)
    }

    guard let outcome else {
      throw .beingFinished(run.identifier.text)
    }

    return try outcome.get()
  }

  /// With the run's lock held: the run is still open, and the finish point reads it.
  private func finish(
    _ run: OpenVerifyRun,
    in resolved: ResolvedWorkspace,
    reloading: any WorkspaceReloading,
    through finishing: any FinishPointing,
    store: VerifyStore,
  ) async -> Result<VerifiedRun, VerifyError> {
    let open: OpenRun

    do {
      open = try store.writer.reopenRun(
        run.identifier,
        in: resolved.workspace.root,
      )
    } catch {
      guard case .sealed = error else {
        return .failure(.storage(error.description))
      }

      return .failure(.alreadySealed(run.identifier.text))
    }

    do {
      return try await .success(
        finishing.finish(
          open,
          stamp: run.stamp,
          in: resolved,
          ran: [:],
          reloading: reloading,
        ),
      )
    } catch {
      return .failure(error)
    }
  }
}

extension Result where Success == any FinishPointing, Failure == StoreSchemaLoadingError {
  /// The finish point, or the refusal that the store's schemas could not be loaded.
  func opened() throws(VerifyError) -> any FinishPointing {
    switch self {
    case let .success(point):
      return point
    case let .failure(error):
      throw .storage("the store's schemas could not be loaded: \(error)")
    }
  }
}

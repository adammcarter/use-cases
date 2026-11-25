import Foundation

/// Runs the commands of the bridge settings between the start point and the finish point.
public struct VerifyRunner: VerifyRunning {
  let opener: any RunOpening
  let store: Result<VerifyStore, StoreSchemaLoadingError>
  let finishPoint: Result<any FinishPointing, StoreSchemaLoadingError>
  let executor: any RunCommandExecuting
  let cancellation: any CancellationScoping

  /// A runner over the real file system, the system clock and real processes, with SIGINT and
  /// SIGTERM stopping the command that runs. The signals are taken over for as long as the
  /// request lasts, and given back when it ends.
  public init() {
    self.init(
      makeScope: {
        SignalCancellationScope()
      },
    )
  }

  /// A runner that asks the observer `cancellation` makes whether the request was cancelled,
  /// taking over no signal.
  ///
  /// - Parameter cancellation: Makes the observer the commands and transformers are stopped by.
  public init(cancellation: @escaping @Sendable () -> any CancellationObserving) {
    self.init(
      makeScope: {
        ObservedCancellationScope(makeObserver: cancellation)
      },
    )
  }

  private init(makeScope: () -> any CancellationScoping) {
    let clock = SystemTimekeeper()
    let store = Result { () throws(StoreSchemaLoadingError) in
      try VerifyStore(clock: clock)
    }
    let scope = makeScope()
    let finishScope = makeScope()

    self.init(
      opener: VerifyStarter(),
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
          cancellation: finishScope,
          clock: clock,
        )
      },
      executor: RunCommandExecutor(
        supervisor: ProcessSupervisor(cancellation: scope),
        writer: store.map(\.writer),
      ),
      cancellation: scope,
    )
  }

  init(
    opener: any RunOpening,
    store: Result<VerifyStore, StoreSchemaLoadingError>,
    finishPoint: Result<any FinishPointing, StoreSchemaLoadingError>,
    executor: any RunCommandExecuting,
    cancellation: any CancellationScoping,
  ) {
    self.opener = opener
    self.store = store
    self.finishPoint = finishPoint
    self.executor = executor
    self.cancellation = cancellation
  }

  public func run(
    _ request: VerifyRunRequest,
    in resolved: ResolvedWorkspace,
    reloading: any WorkspaceReloading,
  ) async throws(VerifyError) -> VerifiedRun {
    let store = try store.opened()
    let finishing = try finishPoint.opened()

    // The signals are ours from the first step to the last, so none of them falls between two
    // parts of the request, where the default action would end the process with the run open.
    await cancellation.begin()
    let outcome = await opened(
      request,
      in: resolved,
      reloading: reloading,
      store: store,
      finishing: finishing,
    )
    await cancellation.end()

    return try outcome.get()
  }
}

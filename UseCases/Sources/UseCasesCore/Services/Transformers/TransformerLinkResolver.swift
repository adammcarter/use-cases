import Foundation

/// Runs the links job of each link transformer in turn and checks what comes back.
public struct TransformerLinkResolver: TransformerLinkProviding {
  private let makeRunner: @Sendable (any CancellationObserving) -> any TransformerRunning
  private let cancellation: any CancellationScoping
  private let requestBuilder: any LinksRequestBuilding
  private let responseReader: any LinksResponseReading
  private let linkChecker: any TransformerLinkChecking

  /// A resolver as production builds it: bundled transformers beside the running `use-cases`,
  /// SIGINT and SIGTERM stopping a transformer that runs, and 120 seconds for each to answer. The
  /// signals are taken over only while a transformer has to run, so a workspace without one never
  /// does, and are given back when the links are known.
  public init() {
    self.init(scope: SignalCancellationScope())
  }

  /// A resolver that asks the observer `cancellation` makes whether the run was cancelled. The
  /// observer is made only when a transformer has to run.
  ///
  /// - Parameter cancellation: Makes the observer a running transformer is stopped by.
  public init(cancellation: @escaping @Sendable () -> any CancellationObserving) {
    self.init(scope: ObservedCancellationScope(makeObserver: cancellation))
  }

  private init(scope: any CancellationScoping) {
    let fileSystem = LocalFileSystem()

    self.init(
      makeRunner: { cancellation in
        TransformerRunner.production(cancellation: cancellation)
      },
      cancellation: scope,
      requestBuilder: LinksRequestBuilder(),
      responseReader: LinksResponseReader(),
      linkChecker: TransformerLinkChecker(
        placer: ManualBindingResolver(
          fileSystem: fileSystem,
          pathFinder: ExactPathFinder(fileSystem: fileSystem),
          rangeConverter: ManualRangeConverter(),
        ),
      ),
    )
  }

  init(
    makeRunner: @escaping @Sendable (any CancellationObserving) -> any TransformerRunning,
    cancellation: any CancellationScoping,
    requestBuilder: any LinksRequestBuilding,
    responseReader: any LinksResponseReading,
    linkChecker: any TransformerLinkChecking,
  ) {
    self.makeRunner = makeRunner
    self.cancellation = cancellation
    self.requestBuilder = requestBuilder
    self.responseReader = responseReader
    self.linkChecker = linkChecker
  }

  public func links(for workspace: LoadedWorkspace) async throws(TransformerLinkingError)
    -> TransformedLinks
  {
    do {
      return try await resolve(workspace)
    } catch {
      throw TransformerLinkingError(error)
    }
  }

  private func resolve(_ workspace: LoadedWorkspace) async throws(TransformerError)
    -> TransformedLinks
  {
    guard let entries = workspace.bridge?.links, !entries.isEmpty else {
      return .none
    }

    await cancellation.begin()

    let found: LinkFindings

    do {
      found = try await runLinksJobs(
        entries,
        for: workspace,
        by: makeRunner(cancellation),
      )
    } catch {
      await cancellation.end()

      throw error
    }

    // A signal that came after the last transformer answered, before the signals were given
    // back, is still a cancellation.
    let cancelled = await cancellation.isCancelled()
    await cancellation.end()

    guard !cancelled else {
      throw .cancelled
    }

    return TransformedLinks(findings: found)
  }

  private func runLinksJobs(
    _ entries: [BridgeLinkTransformer],
    for workspace: LoadedWorkspace,
    by runner: any TransformerRunning,
  ) async throws(TransformerError) -> LinkFindings {
    let targets = LinkTargets(workspace.useCases)
    let context = workspace.discoveryContext
    var files = BoundFiles()
    var found = LinkFindings.empty

    for entry in entries {
      let name = entry.transformer.name
      let response = try await runner.run(
        entry.transformer,
        job: .links,
        request: requestBuilder.request(
          for: workspace,
          settings: entry.settings,
        ),
        in: workspace.root,
      )
      let answer = try responseReader.read(
        response,
        from: name,
      )

      for link in answer.links {
        try found.links.append(
          linkChecker.resolve(
            link,
            from: name,
            among: targets,
            context: context,
            files: &files,
          ),
        )
      }

      guard let diagnostics = answer.diagnostics else {
        throw .malformedResponse(
          name: name,
          reason: "diagnostics: this is required",
        )
      }

      found.diagnostics += diagnostics.map { text in
        .transformerSaid(
          text,
          by: name,
        )
      }
    }

    return found
  }
}

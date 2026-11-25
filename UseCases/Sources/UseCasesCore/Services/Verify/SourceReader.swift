import Foundation

/// Reads a report in place with the validation's results transformer, and seals the bytes that
/// were read: the folder is digested before and after, and a report that changed while it was
/// read gives no results (chapter 12 §15).
struct SourceReader: SourceReading {
  private let access: any StoreFileAccessing
  private let reports: any ReportDigesting
  private let requestBuilder: any ResultsRequestBuilding
  private let responseReader: any TransformerResultsReading

  init(
    access: any StoreFileAccessing,
    reports: (any ReportDigesting)? = nil,
    requestBuilder: any ResultsRequestBuilding = ResultsRequestBuilder(),
    responseReader: any TransformerResultsReading = TransformerResultsReader(),
  ) {
    self.access = access
    self.reports = reports ?? ReportDigester(access: access)
    self.requestBuilder = requestBuilder
    self.responseReader = responseReader
  }

  func read(
    _ validation: BridgeValidation,
    run: OpenRun,
    in resolved: ResolvedWorkspace,
    ran: RanCommand?,
    using runner: any TransformerRunning,
  ) async -> SourceOutcome {
    let context = ReadingContext(
      validation: validation,
      run: run,
      resolved: resolved,
      ran: ran,
      runner: runner,
    )

    if let failure = ran?.failure {
      return context.outcome(error: failure)
    }
    if let missing = noReport(in: context) {
      return context.outcome(error: missing)
    }

    return await readInPlace(context)
  }

  /// "Nothing at `{report}`, or an empty reports folder" (chapter 13 §7 step 3b): the name of the
  /// error says whose path it was.
  private func noReport(in context: ReadingContext) -> String? {
    let isPresent: Bool

    do {
      if context.validation.report != nil {
        isPresent = try access.kind(of: context.report) != nil
      } else {
        isPresent = try !access.entries(in: context.folder).isEmpty
      }
    } catch {
      return "the report cannot be looked at: \(error)"
    }

    guard !isPresent else {
      return nil
    }

    let place = context.ran == nil ? "the path `--start` gave" : "{report}"

    return "no report: nothing was written to \(context.paths.relative) (\(place))"
  }

  private func readInPlace(_ context: ReadingContext) async -> SourceOutcome {
    let before = digests(of: context)

    // A symlink or another file that is not a regular file is never followed: the source gives
    // no results, and the run error names it.
    if let unusable = before.unusable.first {
      return context.outcome(error: unusable.message)
    }

    let answer: TransformerResults

    do {
      answer = try await ask(context)
    } catch {
      guard error != .cancelled else {
        return context.outcome(
          readReports: before.digests,
          isCancelled: true,
        )
      }

      return context.outcome(
        error: "transformer error, no results used: \(error)",
        readReports: before.digests,
      )
    }

    let after = digests(of: context)

    guard after == before else {
      return context.outcome(
        error: "report changed while it was read",
        readReports: before.digests,
      )
    }

    return accepted(
      answer,
      reading: before.digests,
      context: context,
    )
  }

  /// The results of a source whose report was read whole. A command that exited non-zero with no
  /// failing test left no usable report: the build broke (chapter 13 §7 step 3f).
  private func accepted(
    _ answer: TransformerResults,
    reading: [FileDigest],
    context: ReadingContext,
  ) -> SourceOutcome {
    if let code = context.ran?.exitCode, code != 0,
       !answer.results.contains(where: { $0.status == .fail || $0.status == .error })
    {
      return context.outcome(
        error: "command exited \(code) without any failing test (build failure?)",
        readReports: reading,
      )
    }

    return SourceOutcome(
      source: context.source(diagnostics: answer.diagnostics),
      results: answer.results,
      unlinked: answer.unlinked,
      readReports: reading,
      isCancelled: false,
    )
  }

  private func ask(_ context: ReadingContext) async throws(TransformerError) -> TransformerResults {
    let name = context.validation.transformer.name
    let response = try await context.runner.run(
      context.validation.transformer,
      job: .results,
      request: requestBuilder.request(
        for: context.validation,
        in: context.resolved.workspace,
        links: context.resolved.links,
        reportPath: context.paths.absolute(
          of: context.run.identifier,
          in: context.run.workspace,
        ),
        exitCode: context.ran?.exitCode,
      ),
      in: context.resolved.workspace.root,
    )

    return try responseReader.read(
      response,
      from: name,
      links: context.validationKeys,
    )
  }

  /// The SHA-256 of every file in the validation's reports folder, by path from `reports/`.
  private func digests(of context: ReadingContext) -> ReportDigests {
    reports.digests(
      below: context.folder,
      prefix: "\(context.validation.identifier.text)/",
    )
  }
}

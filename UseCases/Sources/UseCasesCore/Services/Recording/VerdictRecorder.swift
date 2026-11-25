/// Records verdicts as runs of kind `record`: the request is checked and fingerprinted by
/// ``plan(_:in:links:)``, and ``commit(_:)`` allocates, appends and seals (chapter 13 §12).
public struct VerdictRecorder: VerdictRecording {
  private let fingerprinter: any RouteFingerprintComputing
  private let writing: Result<any RunWriting, StoreSchemaLoadingError>
  let reader: any AttachmentReading
  let spooler: any AttachmentSpooling
  private let clock: any Timekeeping

  /// A recorder over the real file system and the system clock.
  public init() {
    let clock = SystemTimekeeper()

    self.init(
      fingerprinter: RouteFingerprintComputer(),
      writing: Result { () throws(StoreSchemaLoadingError) in
        try RunWriter(clock: clock)
      },
      reader: LocalAttachmentReader(),
      spooler: AttachmentSpooler(),
      clock: clock,
    )
  }

  init(
    fingerprinter: any RouteFingerprintComputing,
    writing: Result<any RunWriting, StoreSchemaLoadingError>,
    reader: any AttachmentReading,
    spooler: any AttachmentSpooling = AttachmentSpooler(),
    clock: any Timekeeping,
  ) {
    self.fingerprinter = fingerprinter
    self.writing = writing
    self.reader = reader
    self.spooler = spooler
    self.clock = clock
  }

  public func plan(
    _ request: RecordRequest,
    in workspace: LoadedWorkspace,
    links: LinkResolution,
  ) throws(RecordingError) -> RecordPlan {
    guard let verdict = Verdict(rawValue: request.status) else {
      throw .unknownStatus(request.status)
    }

    let useCase = try useCase(
      named: request.useCase,
      in: workspace,
    )
    let route = try route(
      named: request.route,
      of: useCase,
    )

    if case let .draft(missing) = useCase.definition.authoredState {
      throw .draft(
        useCase: useCase.identifier.text,
        missing: missing.map(\.words),
      )
    }

    let fingerprint = try fingerprint(
      of: route.identifier,
      in: useCase,
      workspace: workspace,
      links: links,
    )
    let attachments = try keptAttachments(at: request.attachments)

    return RecordPlan(
      workspace: workspace.root,
      result: RecordPlan.PlannedResult(
        useCase: useCase.identifier,
        route: route.identifier,
        fingerprint: fingerprint,
        verdict: verdict,
        message: request.message.flatMap { $0.isEmpty ? nil : $0 },
        attachments: attachments,
      ),
    )
  }

  public func commit(_ plan: RecordPlan) throws(RecordingError) -> RecordedRun {
    let writer: any RunWriting

    switch writing {
    case let .success(found):
      writer = found
    case let .failure(error):
      throw .storage("the store's schemas could not be loaded: \(error)")
    }

    // The kept copies are opened before the run is, so that one that cannot be leaves no run
    // behind.
    let attachments = try attachmentSources(of: plan)

    // The run is held from the moment it appears and until it is sealed, so that `verify --abort`
    // can tell a record in progress from one that was cut off.
    let held: HeldRun

    do {
      held = try writer.openHeldRun(
        kind: .record,
        in: plan.workspace,
      )
    } catch {
      throw .storage(error.description)
    }

    defer {
      held.lock.release()
    }

    do {
      let run = held.run
      let kept = try writer.ingest(
        attachments,
        into: run,
      )
      let result = storedResult(
        of: plan,
        attachments: kept,
      )

      try writer.append(
        result,
        to: run,
      )
      _ = try writer.seal(
        run,
        termination: .completed,
      )

      return recorded(
        run,
        result: result,
      )
    } catch {
      throw .storage(error.description)
    }
  }

  private func fingerprint(
    of route: RouteIdentifier,
    in useCase: LoadedUseCase,
    workspace: LoadedWorkspace,
    links: LinkResolution,
  ) throws(RecordingError) -> RouteFingerprint {
    let fingerprints = fingerprinter.fingerprints(
      of: workspace,
      links: links,
    )

    guard !fingerprints.isInvalid else {
      throw .invalidWorkspace(problems: fingerprints.problems)
    }
    guard let text = fingerprints.fingerprint(
      useCase: useCase.identifier.text,
      route: route.text,
    ) else {
      throw .noFingerprint(
        useCase: useCase.identifier.text,
        route: route.text,
      )
    }

    do {
      return try RouteFingerprint(validating: text)
    } catch {
      throw .storage("\(error)")
    }
  }

  private func storedResult(
    of plan: RecordPlan,
    attachments: [ResultAttachment],
  ) -> StoredResult {
    StoredResult(
      useCase: plan.result.useCase,
      route: plan.result.route,
      fingerprint: plan.result.fingerprint,
      verdict: plan.result.verdict,
      detail: StoredResultDetail(
        recordedAt: clock.now().storeTimestamp,
        origin: .recorded,
        message: plan.result.message,
        attachments: attachments,
      ),
    )
  }

  private func recorded(
    _ run: OpenRun,
    result: StoredResult,
  ) -> RecordedRun {
    RecordedRun(
      runIdentifier: run.identifier.text,
      createdAt: run.manifest.createdAt,
      useCase: result.useCase.text,
      route: result.route.text,
      fingerprint: result.fingerprint.text,
      status: result.verdict.rawValue,
      recordedAt: result.detail?.recordedAt ?? "",
      message: result.detail?.message,
      attachments: (result.detail?.attachments ?? []).map(RecordedAttachment.init),
    )
  }
}

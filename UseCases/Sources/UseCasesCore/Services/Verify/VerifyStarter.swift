import Foundation

/// The start point of a verify run.
public struct VerifyStarter: VerifyStarting, RunOpening {
  /// What there is to say when the bridge settings have no validation (chapter 13 §13).
  static let nothingToStart =
    "no validations set up in use-cases-bridge.yml, so nothing to start; "
      + "record verdicts with `use-cases record`"

  private let fingerprinter: any RouteFingerprintComputing
  private let store: Result<VerifyStore, StoreSchemaLoadingError>
  private let digester: any ValidationsDigesting

  /// A starter over the real file system and the system clock.
  public init() {
    self.init(
      fingerprinter: RouteFingerprintComputer(),
      store: Result { () throws(StoreSchemaLoadingError) in
        try VerifyStore()
      },
      digester: ValidationsDigester(),
    )
  }

  init(
    fingerprinter: any RouteFingerprintComputing,
    store: Result<VerifyStore, StoreSchemaLoadingError>,
    digester: any ValidationsDigesting,
  ) {
    self.fingerprinter = fingerprinter
    self.store = store
    self.digester = digester
  }

  public func prepare(
    _ request: VerifyStartRequest,
    in resolved: ResolvedWorkspace,
  ) throws(VerifyError) -> PreparedVerifyStart {
    try prepare(
      request,
      in: resolved,
      openedBy: .start,
    )
  }

  func prepare(
    _ request: VerifyStartRequest,
    in resolved: ResolvedWorkspace,
    openedBy opener: RunOpener,
  ) throws(VerifyError) -> PreparedVerifyStart {
    let workspace = resolved.workspace
    let selected = try Self.select(
      request.only,
      among: workspace.bridge?.validations ?? [],
    )

    guard !selected.isEmpty else {
      return PreparedVerifyStart(
        draft: nil,
        selected: [],
        root: workspace.root,
        others: OpenRuns(
          open: [],
          damaged: [],
          records: [],
        ),
      )
    }

    let store = try store.opened()

    return try PreparedVerifyStart(
      draft: draft(
        of: selected,
        in: resolved,
        openedBy: opener,
      ),
      selected: selected,
      root: workspace.root,
      others: opener == .start
        ? store.allRuns(in: workspace.root)
        : OpenRuns(
          open: [],
          damaged: [],
          records: [],
        ),
    )
  }

  public func commit(_ prepared: PreparedVerifyStart) throws(VerifyError) -> StartedVerifyRun {
    guard let draft = prepared.draft else {
      return StartedVerifyRun(
        runIdentifier: nil,
        selected: [],
        reports: [],
        notes: [Self.nothingToStart],
      )
    }

    let writer = try store.opened().writer
    let run: OpenRun

    do {
      run = try writer.openVerifyRun(
        draft,
        in: prepared.root,
      )
    } catch {
      throw .storage(error.description)
    }

    return StartedVerifyRun(
      runIdentifier: run.identifier.text,
      selected: prepared.selected.map(\.identifier.text),
      reports: prepared.selected.map { validation in
        StartedReport(
          validation: validation.identifier.text,
          path: ReportPaths(validation: validation).absolute(
            of: run.identifier,
            in: prepared.root,
          ),
        )
      },
      notes: Self.notes(
        for: run.identifier,
        others: prepared.others,
      ),
    )
  }

  func open(_ prepared: PreparedVerifyStart) throws(VerifyError) -> OpenedRun? {
    guard let draft = prepared.draft else {
      return nil
    }

    let writer = try store.opened().writer
    let held: HeldRun

    do {
      held = try writer.openHeldVerifyRun(
        draft,
        in: prepared.root,
      )
    } catch {
      throw .storage(error.description)
    }

    return OpenedRun(
      run: held.run,
      lock: held.lock,
      selected: prepared.selected,
    )
  }

  /// The validations `--only` names, in the order of the bridge settings; all of them when it
  /// names none.
  static func select(
    _ names: [String],
    among validations: [BridgeValidation],
  ) throws(VerifyError) -> [BridgeValidation] {
    guard !names.isEmpty else {
      return validations
    }

    let known = validations.map(\.identifier.text)
    let unknown = names.filter { name in
      !known.contains(name)
    }

    guard unknown.isEmpty else {
      throw .unknownValidations(
        unknown,
        known: known,
      )
    }

    return validations.filter { validation in
      names.contains(validation.identifier.text)
    }
  }

  private func draft(
    of selected: [BridgeValidation],
    in resolved: ResolvedWorkspace,
    openedBy opener: RunOpener,
  ) throws(VerifyError) -> StartDraft {
    let fingerprints = fingerprinter.fingerprints(
      of: resolved.workspace,
      links: resolved.links,
    )

    guard !fingerprints.isInvalid else {
      throw .invalidWorkspace(problems: fingerprints.problems)
    }

    return try StartDraft(
      openedBy: opener,
      selected: selected.map(\.identifier),
      validationsDigest: digester.digest(of: selected),
      routes: Self.routes(of: fingerprints),
      files: fingerprints.fileDigests,
      sources: selected.map { validation in
        RunSource.planned(for: validation)
      },
    )
  }

  private static func routes(of fingerprints: RouteFingerprints) throws(VerifyError)
    -> [StartedRoute]
  {
    var routes: [StartedRoute] = []

    for route in fingerprints.routes {
      do {
        try routes.append(
          StartedRoute(
            useCase: UseCaseIdentifier(validating: route.useCase),
            route: RouteIdentifier(validating: route.route),
            fingerprint: RouteFingerprint(validating: route.fingerprint),
          ),
        )
      } catch {
        throw .storage("route \(route.route) of \(route.useCase) has a malformed fingerprint")
      }
    }

    return routes
  }

  /// What `--start` says: where the tests write, and which runs are still open beside this one.
  private static func notes(
    for run: RunIdentifier,
    others: OpenRuns,
  ) -> [String] {
    var notes = [
      "now run your tests, each writing its report to the path in `reports`; then "
        + "`use-cases verify --finish --run-id \(run.text)` records their results",
    ]

    if !others.open.isEmpty {
      let ids = others.open.map(\.identifier.text).joined(separator: ", ")
      notes.append(
        "other runs are still open: \(ids); `use-cases verify --abort --run-id <id>` closes "
          + "one nobody will finish",
      )
    }

    notes += others.damaged.map(\.message)

    return notes
  }
}

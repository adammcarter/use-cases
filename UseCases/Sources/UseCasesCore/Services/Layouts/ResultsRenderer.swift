import Foundation

/// Draws the results of an applied proposal from the proposal file and the workspace as `status`
/// judges it. A proposal is applied when every removal is gone and every save's promise
/// (chapter 21 §6) is the one the workspace holds: how a use case is proven may differ.
public struct ResultsRenderer: ResultsRendering {
  private let reader: any ProposalFileReading
  private let resolver: any ProposalChangeResolving
  private let judge: any StatusJudging
  private let fingerprinter: any PromiseFingerprinting

  /// Makes the renderer.
  ///
  /// - Parameter workingDirectory: Where a relative path given to `--file` is read from.
  public init(workingDirectory: URL) {
    self.init(
      reader: ProposalFileReader(workingDirectory: workingDirectory),
      resolver: ProposalChangeResolver(),
      judge: StatusJudge(),
      fingerprinter: PromiseFingerprinter(),
    )
  }

  init(
    reader: any ProposalFileReading,
    resolver: any ProposalChangeResolving,
    judge: any StatusJudging,
    fingerprinter: any PromiseFingerprinting,
  ) {
    self.reader = reader
    self.resolver = resolver
    self.judge = judge
    self.fingerprinter = fingerprinter
  }

  public func results(
    readingFrom argument: String,
    in workspace: LoadedWorkspace,
    links: LinkResolution,
  ) throws(LayoutRenderingError) -> ResultsLayout {
    let proposal = try reader.read(argument)

    try resolver.checkReferences(
      of: proposal,
      in: workspace,
    )

    let status: WorkspaceStatus

    do {
      status = try judge.judge(
        workspace,
        links: links,
      )
    } catch {
      throw .status(error)
    }

    for removed in proposal.batch.removals where status.holds(removed) {
      throw .notApplied(identifier: removed)
    }

    let saved = try proposal.batch.saves.map { save throws(LayoutRenderingError) in
      let identifier = save.identifier.text

      guard
        let entry = status.useCase(identifier),
        let held = workspace.useCases.first(where: { held in held.identifier == save.identifier }),
        try promise(of: save.definition, as: save.identifier)
        == promise(of: held.definition, as: held.identifier)
      else {
        throw .notApplied(identifier: identifier)
      }

      return ResultUseCase(entry)
    }

    return ResultsLayout(
      title: proposal.title,
      useCases: saved,
      removed: proposal.batch.removals,
      gatePasses: status.gate(strict: false).passed,
    )
  }

  /// The fingerprint of what the use case promises, which a different title, intent, scenario or
  /// tier changes and a different route, link or sign-off does not.
  private func promise(
    of definition: UseCaseDefinition,
    as identifier: UseCaseIdentifier,
  ) throws(LayoutRenderingError) -> String {
    do {
      return try fingerprinter.fingerprint(
        of: PromiseFingerprintInput(
          definition: definition,
          identifier: identifier,
        ),
      )
    } catch {
      throw .unfingerprintable(
        identifier: identifier.text,
        reason: "\(error)",
      )
    }
  }
}

private extension WorkspaceStatus {
  func holds(_ identifier: String) -> Bool {
    useCase(identifier) != nil
  }

  func useCase(_ identifier: String) -> UseCaseStatus? {
    useCases.first { held in
      held.identifier.isExactlyEqual(to: identifier)
    }
  }
}

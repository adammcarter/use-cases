/// Finds each use case of a proposal in the workspace, and refuses a proposal that points at a
/// use case or a scenario that is not there rather than ignoring the pointer.
struct ProposalChangeResolver: ProposalChangeResolving {
  func changes(
    of proposal: ProposalFile,
    in workspace: LoadedWorkspace,
  ) throws(LayoutRenderingError) -> [ResolvedChange] {
    var found: [ResolvedChange] = []

    for identifier in proposal.batch.removals {
      let before = try existing(
        identifier,
        in: workspace,
      )

      found.append(
        ResolvedChange(
          identifier: identifier,
          fit: .replaces,
          before: before.definition,
          shown: before.definition,
        ),
      )
    }

    for save in proposal.batch.saves {
      let before = workspace.useCases.first { held in
        held.identifier == save.identifier
      }?.definition

      if before == nil, proposal.fits[save.identifier.text] != nil {
        throw pointer(
          "`fits` names '\(save.identifier.text.displayEscaped)', which is new: "
            + "its fit follows from the batch",
          in: proposal,
        )
      }

      found.append(
        ResolvedChange(
          identifier: save.identifier.text,
          fit: before == nil ? .new : proposal.fits[save.identifier.text] ?? .changes,
          before: before,
          shown: save.definition,
        ),
      )
    }

    try found += untouched(
      of: proposal,
      in: workspace,
    )
    try checkPointers(of: proposal)

    return ProposalFit.allCases.flatMap { fit in
      found.filter { change in
        change.fit == fit
      }
    }
  }

  func checkReferences(
    of proposal: ProposalFile,
    in workspace: LoadedWorkspace,
  ) throws(LayoutRenderingError) {
    _ = try untouched(
      of: proposal,
      in: workspace,
    )
    try checkPointers(of: proposal)
  }

  private func untouched(
    of proposal: ProposalFile,
    in workspace: LoadedWorkspace,
  ) throws(LayoutRenderingError) -> [ResolvedChange] {
    var found: [ResolvedChange] = []

    for identifier in proposal.untouched {
      let held = try existing(
        identifier,
        in: workspace,
      )

      if proposal.names(identifier) {
        throw .invalidProposal(
          name: proposal.name,
          problem: "'\(identifier.displayEscaped)' is in the batch, so it is not untouched",
        )
      }

      found.append(
        ResolvedChange(
          identifier: identifier,
          fit: .untouched,
          before: held.definition,
          shown: held.definition,
        ),
      )
    }

    return found
  }

  private func existing(
    _ identifier: String,
    in workspace: LoadedWorkspace,
  ) throws(LayoutRenderingError) -> LoadedUseCase {
    guard
      let held = workspace.useCases.first(where: { held in
        held.identifier.text.isExactlyEqual(to: identifier)
      })
    else {
      throw .unknownUseCase(identifier: identifier)
    }

    return held
  }

  /// `fits` and `golden` speak of what the batch saves; `you_see` of any use case the proposal
  /// shows.
  private func checkPointers(
    of proposal: ProposalFile,
  ) throws(LayoutRenderingError) {
    let saved = Dictionary(
      uniqueKeysWithValues: proposal.batch.saves.map { save in
        (save.identifier.text, save.definition)
      },
    )

    for identifier in proposal.fits.keys.sorted() where saved[identifier] == nil {
      throw pointer(
        "`fits` names '\(identifier.displayEscaped)', which the batch does not save",
        in: proposal,
      )
    }

    for identifier in proposal.youSee.keys.sorted()
      where !proposal.names(identifier) && !proposal.untouched.contains(identifier)
    {
      throw pointer(
        "`you_see` names '\(identifier.displayEscaped)', which the proposal neither saves, "
          + "removes nor leaves untouched",
        in: proposal,
      )
    }

    for (identifier, scenarios) in proposal.golden.sorted(by: { $0.key < $1.key }) {
      guard let definition = saved[identifier] else {
        throw pointer(
          "`golden` names '\(identifier.displayEscaped)', which the batch does not save",
          in: proposal,
        )
      }

      for scenario in scenarios
        where !definition.scenarios.contains(where: { $0.identifier.text == scenario })
      {
        throw pointer(
          "`golden` names scenario '\(scenario.displayEscaped)', "
            + "which '\(identifier.displayEscaped)' does not have",
          in: proposal,
        )
      }
    }
  }

  private func pointer(
    _ problem: String,
    in proposal: ProposalFile,
  ) -> LayoutRenderingError {
    .invalidProposal(
      name: proposal.name,
      problem: problem,
    )
  }
}

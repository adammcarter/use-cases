import Foundation

/// Plans a batch as one run of edits: every removal, then every addition, then every update,
/// whatever order the file lists them in (chapter 16 §14, ADR 031). Whether a save adds or
/// updates is decided from its id and the workspace as it is.
struct UseCaseBatchPlanner: UseCaseBatchPlanning {
  private let placer: any UseCasePlacing
  private let stamper: any ApprovalStamping
  private let calendar: any CalendarDayTelling
  private let sequences: any UseCaseEditSequenceMaking
  private let warner: any StillMarkedWarning

  init(
    placer: any UseCasePlacing = UseCasePlacer(),
    stamper: any ApprovalStamping = ApprovalStamper(),
    calendar: any CalendarDayTelling = LocalCalendarDay(),
    sequences: any UseCaseEditSequenceMaking = UseCaseEditSequenceMaker(),
    warner: any StillMarkedWarning = StillMarkedWarner(),
  ) {
    self.placer = placer
    self.stamper = stamper
    self.calendar = calendar
    self.sequences = sequences
    self.warner = warner
  }

  func plan(
    _ batch: UseCaseBatch,
    approvedBy approver: ApproverName?,
    in workspace: LoadedWorkspace,
    links: [ResolvedLink],
  ) throws(UseCaseBatchError) -> UseCaseBatchChange {
    try batch.requireEachOnce()

    let removals = try useCasesToRemove(
      in: batch,
      of: workspace,
    )
    let saves = Self.saves(
      of: batch,
      in: workspace,
    )
    let signing = approver.map { approver in
      BatchSigning(
        approver: approver,
        day: calendar.today(),
      )
    }

    var run = BatchRun(sequence: sequences.sequence(for: workspace))

    for useCase in removals {
      try remove(
        useCase,
        in: &run,
      )
    }

    run.warnings = warner.warnings(
      for: removals.map(\.identifier.text),
      in: links,
    ) + run.warnings

    for save in saves where save.existing == nil {
      try add(
        save.checked,
        signing: signing,
        in: &run,
      )
    }

    for case let (checked, existing?) in saves {
      try update(
        existing,
        from: checked,
        signing: signing,
        in: &run,
      )
    }

    return UseCaseBatchChange(
      useCases: run.useCases,
      root: workspace.root,
      writes: run.sequence.writes,
      warnings: run.warnings,
      expectations: run.expectations,
    )
  }

  // MARK: - The three kinds of change

  private func remove(
    _ useCase: LoadedUseCase,
    in run: inout BatchRun,
  ) throws(UseCaseBatchError) {
    let edited: EditedDefinitionFile

    do {
      edited = try run.sequence.removing(useCase)
    } catch {
      throw .editing(error)
    }

    run.record(
      BatchedUseCase(
        identifier: useCase.identifier.text,
        file: useCase.file.text,
        action: .removed,
      ),
      expecting: .absent(identifier: useCase.identifier),
      warnings: edited.droppedComments,
    )
  }

  private func add(
    _ checked: CheckedUseCase,
    signing: BatchSigning?,
    in run: inout BatchRun,
  ) throws(UseCaseBatchError) {
    let definition = try definition(
      of: checked,
      existing: nil,
      signing: signing,
    )
    let edited: EditedDefinitionFile
    let action: UseCaseChangeAction

    do {
      let placement = try placer.place(
        checked.identifier,
        in: run.sequence.workspace,
      )

      edited = try run.sequence.adding(
        definition,
        as: checked.identifier,
        placed: placement,
      )

      if case .new = placement {
        action = .created
      } else {
        action = .added
      }
    } catch {
      throw .editing(error)
    }

    run.record(
      BatchedUseCase(
        identifier: checked.identifier.text,
        file: edited.change.path,
        action: action,
      ),
      expecting: .present(
        identifier: checked.identifier,
        file: edited.change.workspacePath,
        definition: definition,
      ),
      warnings: edited.droppedComments,
    )
  }

  private func update(
    _ existing: LoadedUseCase,
    from checked: CheckedUseCase,
    signing: BatchSigning?,
    in run: inout BatchRun,
  ) throws(UseCaseBatchError) {
    let definition = try definition(
      of: checked,
      existing: existing,
      signing: signing,
    )
    var warnings: [String] = []
    var action = UseCaseChangeAction.unchanged

    if definition != existing.definition {
      do {
        warnings = try run.sequence.replacing(
          existing,
          with: definition,
        ).droppedComments
      } catch {
        throw .editing(error)
      }

      action = .replaced
    }

    run.record(
      BatchedUseCase(
        identifier: existing.identifier.text,
        file: existing.file.text,
        action: action,
      ),
      expecting: .present(
        identifier: existing.identifier,
        file: existing.file,
        definition: definition,
      ),
      warnings: warnings,
    )
  }

  // MARK: - Reading the batch

  /// A save never writes a sign-off of its own; a signed-off batch writes the batch's.
  private func definition(
    of checked: CheckedUseCase,
    existing: LoadedUseCase?,
    signing: BatchSigning?,
  ) throws(UseCaseBatchError) -> UseCaseDefinition {
    let kept: UseCaseDefinition

    do {
      kept = try checked.keepingApproval(of: existing)
    } catch {
      throw .editing(error)
    }

    guard let signing else {
      return kept
    }

    do {
      return try stamper.signed(
        kept,
        as: checked.identifier,
        by: signing.approver,
        on: signing.day,
      )
    } catch {
      throw .stamping(error)
    }
  }

  private func useCasesToRemove(
    in batch: UseCaseBatch,
    of workspace: LoadedWorkspace,
  ) throws(UseCaseBatchError) -> [LoadedUseCase] {
    var removals: [LoadedUseCase] = []

    for identifier in batch.removals {
      try removals.append(
        useCase(
          named: identifier,
          in: workspace,
        ),
      )
    }

    return removals
  }

  /// Each save with the use case of the workspace it is the new form of, if there is one.
  private static func saves(
    of batch: UseCaseBatch,
    in workspace: LoadedWorkspace,
  ) -> [(checked: CheckedUseCase, existing: LoadedUseCase?)] {
    batch.saves.map { checked in
      (
        checked: checked,
        existing: workspace.useCases.first { held in
          held.identifier == checked.identifier
        },
      )
    }
  }

  private func useCase(
    named identifier: String,
    in workspace: LoadedWorkspace,
  ) throws(UseCaseBatchError) -> LoadedUseCase {
    guard
      let found = workspace.useCases.first(where: { held in
        held.identifier.text.isExactlyEqual(to: identifier)
      })
    else {
      throw .editing(.unknown(identifier: identifier))
    }

    return found
  }
}

/// Who signed the batch off, and the day.
private struct BatchSigning {
  let approver: ApproverName
  let day: String
}

/// A batch being planned: the edits so far and what has been said of each use case.
private struct BatchRun {
  var sequence: any UseCaseEditSequencing
  var useCases: [BatchedUseCase] = []
  var warnings: [String] = []
  var expectations: [UseCaseExpectation] = []

  mutating func record(
    _ useCase: BatchedUseCase,
    expecting expectation: UseCaseExpectation,
    warnings: [String],
  ) {
    useCases.append(useCase)
    expectations.append(expectation)
    self.warnings += warnings
  }
}

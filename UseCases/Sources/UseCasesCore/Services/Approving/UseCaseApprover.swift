import Foundation

/// Signs use cases off by rewriting each one with its `approved` record, one after another, so
/// that several use cases of one file all keep their sign-off.
public struct UseCaseApprover: UseCaseApproving {
  private let stamper: any ApprovalStamping
  private let calendar: any CalendarDayTelling
  private let sequences: any UseCaseEditSequenceMaking

  /// Makes the approver, which dates a sign-off by the calendar day of this machine.
  public init() {
    self.init(
      stamper: ApprovalStamper(),
      calendar: LocalCalendarDay(),
      sequences: UseCaseEditSequenceMaker(),
    )
  }

  init(
    stamper: any ApprovalStamping,
    calendar: any CalendarDayTelling,
    sequences: any UseCaseEditSequenceMaking = UseCaseEditSequenceMaker(),
  ) {
    self.stamper = stamper
    self.calendar = calendar
    self.sequences = sequences
  }

  public func plan(
    approving identifiers: [String],
    all: Bool,
    by approver: String,
    in workspace: LoadedWorkspace,
  ) throws(UseCaseApprovingError) -> UseCaseApprovalChange {
    let name: ApproverName

    do {
      name = try ApproverName(validating: approver)
    } catch {
      throw .approver(reason: error.message(of: "--by"))
    }

    let targets = try targets(
      named: identifiers,
      all: all,
      in: workspace,
    )
    let day = calendar.today()
    var run = ApprovalRun(sequence: sequences.sequence(for: workspace))

    for useCase in targets {
      try sign(
        useCase,
        by: name,
        on: day,
        in: &run,
      )
    }

    return UseCaseApprovalChange(
      approver: name.text,
      useCases: run.approved,
      root: workspace.root,
      writes: run.sequence.writes,
      warnings: run.warnings,
      expectations: run.expectations,
    )
  }

  /// A use case already approved as it reads is left as it is.
  private func sign(
    _ useCase: LoadedUseCase,
    by name: ApproverName,
    on day: String,
    in run: inout ApprovalRun,
  ) throws(UseCaseApprovingError) {
    let signed: UseCaseDefinition

    do {
      signed = try stamper.signed(
        useCase.definition,
        as: useCase.identifier,
        by: name,
        on: day,
      )
    } catch {
      throw .stamping(error)
    }

    let signOff = signed.approval
    let isChanged = signed != useCase.definition

    if isChanged, let signOff {
      do {
        try run.warnings += run.sequence.approving(
          useCase,
          with: signOff,
        ).droppedComments
      } catch {
        throw .editing(error)
      }
    }

    run.approved.append(
      ApprovedUseCase(
        identifier: useCase.identifier.text,
        file: useCase.file.text,
        action: isChanged ? .approved : .unchanged,
      ),
    )
    run.expectations.append(
      .present(
        identifier: useCase.identifier,
        file: useCase.file,
        definition: signed,
      ),
    )
  }

  /// Every use case under `all`, by id; otherwise those named, in the order named, each once.
  private func targets(
    named identifiers: [String],
    all: Bool,
    in workspace: LoadedWorkspace,
  ) throws(UseCaseApprovingError) -> [LoadedUseCase] {
    if all, !identifiers.isEmpty {
      throw .namedAndAll
    }

    if !all, identifiers.isEmpty {
      throw .nothingAsked
    }

    guard !all else {
      return workspace.useCases.sorted { lhs, rhs in
        lhs.identifier.text.precedesExactly(rhs.identifier.text)
      }
    }

    var found: [LoadedUseCase] = []

    for identifier in identifiers {
      guard
        let useCase = workspace.useCases.first(where: { held in
          held.identifier.text.isExactlyEqual(to: identifier)
        })
      else {
        throw .editing(.unknown(identifier: identifier))
      }

      if !found.contains(where: { held in held.identifier == useCase.identifier }) {
        found.append(useCase)
      }
    }

    return found
  }
}

/// A sign-off being planned: the edits so far and what has been said of each use case.
private struct ApprovalRun {
  var sequence: any UseCaseEditSequencing
  var approved: [ApprovedUseCase] = []
  var expectations: [UseCaseExpectation] = []
  var warnings: [String] = []
}

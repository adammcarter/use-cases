import Foundation
@testable import UseCasesCore

/// A run of edits that changes nothing and says each edit it is asked for, as a comment it would
/// have dropped, so that the order a planner asks in is the order of the warnings it reports.
struct MockEditSequence: UseCaseEditSequencing {
  let workspace: LoadedWorkspace
  let writes: WritePlan

  mutating func removing(_ useCase: LoadedUseCase) throws(UseCaseEditingError)
    -> EditedDefinitionFile
  {
    try said("removing \(useCase.identifier.text)")
  }

  mutating func adding(
    _: UseCaseDefinition,
    as identifier: UseCaseIdentifier,
    placed _: UseCasePlacement,
  ) throws(UseCaseEditingError) -> EditedDefinitionFile {
    try said("adding \(identifier.text)")
  }

  mutating func replacing(
    _ useCase: LoadedUseCase,
    with _: UseCaseDefinition,
  ) throws(UseCaseEditingError) -> EditedDefinitionFile {
    try said("replacing \(useCase.identifier.text)")
  }

  mutating func approving(
    _ useCase: LoadedUseCase,
    with _: Approval,
  ) throws(UseCaseEditingError) -> EditedDefinitionFile {
    try said("approving \(useCase.identifier.text)")
  }

  private func said(_ words: String) throws(UseCaseEditingError) -> EditedDefinitionFile {
    EditedDefinitionFile(
      change: FileChange(
        action: .replace,
        path: .root,
      ),
      droppedComments: [words],
    )
  }
}

/// Begins the runs of edits of a test: ones that change nothing, over the workspace given.
struct MockEditSequenceMaking: UseCaseEditSequenceMaking {
  let writes: WritePlan

  func sequence(for workspace: LoadedWorkspace) -> any UseCaseEditSequencing {
    MockEditSequence(
      workspace: workspace,
      writes: writes,
    )
  }
}

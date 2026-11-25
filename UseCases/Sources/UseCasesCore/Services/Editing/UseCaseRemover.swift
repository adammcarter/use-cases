/// Removes a use case by taking its lines out of the file that holds it, or the file itself when
/// it was the last use case in it. Nothing in the results store is touched.
public struct UseCaseRemover: UseCaseRemoving {
  private let editor: any DefinitionFileEditing
  private let warner: any StillMarkedWarning

  /// Makes the remover.
  public init() {
    self.init(editor: DefinitionFileEditor())
  }

  init(
    editor: any DefinitionFileEditing,
    warner: any StillMarkedWarning = StillMarkedWarner(),
  ) {
    self.editor = editor
    self.warner = warner
  }

  public func plan(
    removing identifier: String,
    in workspace: LoadedWorkspace,
    links: [ResolvedLink],
  ) throws(UseCaseEditingError) -> UseCaseChange {
    guard
      let useCase = workspace.useCases.first(where: { useCase in
        useCase.identifier.text.isExactlyEqual(to: identifier)
      })
    else {
      throw .unknown(identifier: identifier)
    }

    let edited = try editor.edit(
      .remove(useCase.identifier),
      in: workspace,
    )

    return UseCaseChange(
      identifier: useCase.identifier.text,
      file: useCase.file.text,
      action: .removed,
      root: workspace.root,
      writes: WritePlan(changes: [edited.change]),
      warnings: warner.warnings(
        for: [useCase.identifier.text],
        in: links,
      ) + edited.droppedComments,
      expectation: .absent(identifier: useCase.identifier),
    )
  }
}

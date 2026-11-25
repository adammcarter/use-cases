/// One change to a definition file: a use case written whole, added, taken out or signed off.
enum DefinitionFileEdit: Equatable, Sendable {
  /// A file of its own, holding one use case.
  case create(
    file: WorkspacePath,
    prefix: Namespace,
    definition: UseCaseDefinition,
  )

  /// A use case after the last one of the file.
  case append(
    file: WorkspacePath,
    definition: UseCaseDefinition,
  )

  /// A use case of the workspace, rewritten whole.
  case replace(
    UseCaseIdentifier,
    with: UseCaseDefinition,
  )

  /// A use case of the workspace, taken out.
  case remove(UseCaseIdentifier)

  /// A use case of the workspace given its sign-off, or the one it has replaced by this: its
  /// `approved` field is written and no other line of the file changes.
  case approve(
    UseCaseIdentifier,
    with: Approval,
  )
}

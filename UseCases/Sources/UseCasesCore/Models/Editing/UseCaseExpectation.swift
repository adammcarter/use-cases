/// What a workspace has to hold once a change is made, which the workspace loaded through the
/// plan's view is held to.
enum UseCaseExpectation: Equatable, Sendable {
  /// The use case is there, in this file, as this definition.
  case present(
    identifier: UseCaseIdentifier,
    file: WorkspacePath,
    definition: UseCaseDefinition,
  )

  /// The use case is not there.
  case absent(identifier: UseCaseIdentifier)

  /// What the workspace holds that is not what the change meant, in words; `nil` when it holds
  /// exactly that.
  func divergence(in workspace: LoadedWorkspace) -> String? {
    switch self {
    case let .present(identifier, file, definition):
      guard let found = workspace.useCases.first(where: { $0.identifier == identifier }) else {
        return "\(identifier.text) is not in the workspace the change would leave"
      }

      guard found.file == file else {
        return "\(identifier.text) would be in \(found.file.text), not in \(file.text)"
      }

      guard found.definition == definition else {
        return "\(identifier.text) would not read back as it was sent"
      }

      return nil
    case let .absent(identifier):
      guard workspace.useCases.contains(where: { $0.identifier == identifier }) else {
        return nil
      }

      return "\(identifier.text) would still be in the workspace the change would leave"
    }
  }
}

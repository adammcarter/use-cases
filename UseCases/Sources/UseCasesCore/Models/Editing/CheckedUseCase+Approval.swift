extension CheckedUseCase {
  /// The use case as a save writes it: a save never writes a sign-off, so without one it keeps
  /// the one the use case has, and one that is not the one it has is refused.
  ///
  /// - Parameter existing: The use case of the workspace with this id, if there is one.
  func keepingApproval(of existing: LoadedUseCase?) throws(UseCaseEditingError)
    -> UseCaseDefinition
  {
    let kept = existing?.definition.approval

    guard definition.approval == nil || definition.approval == kept else {
      throw .approvalNotBySave(identifier: identifier.text)
    }

    return definition.approved(kept)
  }
}

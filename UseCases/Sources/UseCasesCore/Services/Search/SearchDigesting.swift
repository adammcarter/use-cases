/// Tells whether the use cases are as they were when a search began (chapter 16 §15).
protocol SearchDigesting: Sendable {
  /// A digest of every use case as it reads, every status and the members of the group the
  /// search is limited to: `nil` for no group, and a group that is not there is told apart from
  /// one with no members.
  func digest(
    of workspace: LoadedWorkspace,
    status: WorkspaceStatus,
    groupMembers: [String]?,
  ) -> String

  /// A digest of the parameters of a search and of the state the search saw. A token made of the
  /// parameters and this seal is read back only when neither has changed.
  func seal(
    of parameters: StoreJSONValue,
    state: String,
  ) -> String
}

/// Reads the group a command line names (chapter 16 §9).
public protocol GroupSelecting: Sendable {
  /// The full ids of the use cases in the group `name` of `workspace`.
  ///
  /// - Parameters:
  ///   - name: The group, as `--group` spells it.
  ///   - workspace: A workspace that loaded, so its groups are valid.
  /// - Returns: The members, DRAFT and READY alike; empty for a group that has none.
  /// - Throws: ``GroupSelectionError`` when no group has the name.
  func members(
    ofGroup name: String,
    in workspace: LoadedWorkspace,
  ) throws(GroupSelectionError) -> Set<String>
}

/// Reads group names against the groups of a loaded workspace.
public struct GroupSelector: GroupSelecting {
  /// Makes the selector.
  public init() {}

  public func members(
    ofGroup name: String,
    in workspace: LoadedWorkspace,
  ) throws(GroupSelectionError) -> Set<String> {
    let group = workspace.groups.first { group in
      group.name.text.isExactlyEqual(to: name)
    }

    guard let group else {
      throw .unknown(
        name: name,
        known: workspace.groups.map(\.name.text),
      )
    }

    return Set(group.members)
  }
}

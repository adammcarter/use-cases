/// What a run of edits does to each file in the end, however many times it touched it: a file
/// emptied and then filled again is replaced, a file made and then emptied is not there to be
/// written at all. A change to a file that was there is held to what the file held when the first
/// edit read it, not to what an edit after that saw: the edits that follow read the edits before
/// them, and a writer must not take that for the file.
struct NetFileChanges: Equatable, Sendable {
  private var firstActions: [WorkspacePath: FileChangeAction] = [:]
  private var firstExpected: [WorkspacePath: [UInt8]] = [:]
  private var latest: [WorkspacePath: FileChange] = [:]

  /// Notes the next change to a file.
  mutating func record(_ change: FileChange) {
    if firstActions[change.workspacePath] == nil {
      firstActions[change.workspacePath] = change.action
      firstExpected[change.workspacePath] = change.expected
    }

    latest[change.workspacePath] = change
  }

  /// The files as they stand after the changes so far: the last change of each, in no order. A
  /// file system with this laid over it is the workspace as the edits have left it.
  var standing: WritePlan {
    WritePlan(changes: Array(latest.values))
  }

  /// What is written in the end: one change a file, by path, for each file whose end differs
  /// from its start.
  var net: WritePlan {
    WritePlan(
      changes: latest.keys.sorted().compactMap { path in
        net(
          of: path,
          startedThere: firstActions[path] != .create,
        )
      },
    )
  }

  private func net(
    of path: WorkspacePath,
    startedThere: Bool,
  ) -> FileChange? {
    guard let last = latest[path] else {
      return nil
    }

    switch (startedThere, last.action) {
    case (true, .delete):
      return .delete(
        path,
        expected: firstExpected[path],
      )
    case (false, .delete):
      return nil
    case (true, .create), (true, .replace):
      return FileChange(
        action: .replace,
        path: path,
        bytes: last.bytes,
        expected: firstExpected[path],
      )
    case (false, .create), (false, .replace):
      return FileChange(
        action: .create,
        path: path,
        bytes: last.bytes,
      )
    }
  }
}

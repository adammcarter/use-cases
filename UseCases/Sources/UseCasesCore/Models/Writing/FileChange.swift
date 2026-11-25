/// One file a plan creates, replaces or deletes, with the bytes it will hold.
public struct FileChange: Equatable, Sendable {
  public let action: FileChangeAction

  let workspacePath: WorkspacePath
  let bytes: [UInt8]

  /// The bytes the file held when the change was planned, for a file that is replaced or deleted;
  /// `nil` where the planner did not record them. The writer refuses the change if the file holds
  /// anything else by the time it writes, so a change made in between is never overwritten.
  let expected: [UInt8]?

  /// Whether the file is made runnable, as a git hook has to be. Only a file that is created can
  /// be.
  let isExecutable: Bool

  /// The file, relative to the workspace root and written with `/`.
  public var path: String {
    workspacePath.text
  }

  init(
    action: FileChangeAction,
    path: WorkspacePath,
    bytes: [UInt8] = [],
    isExecutable: Bool = false,
    expected: [UInt8]? = nil,
  ) {
    self.action = action
    workspacePath = path
    self.bytes = bytes
    self.isExecutable = isExecutable
    self.expected = expected
  }

  /// The same change with the bytes the file held when it was planned.
  func expecting(_ expected: [UInt8]) -> FileChange {
    FileChange(
      action: action,
      path: workspacePath,
      bytes: bytes,
      isExecutable: isExecutable,
      expected: expected,
    )
  }

  /// A file that is not there yet, holding `text`.
  static func create(
    _ path: WorkspacePath,
    text: String,
    isExecutable: Bool = false,
  ) -> FileChange {
    FileChange(
      action: .create,
      path: path,
      bytes: Array(text.utf8),
      isExecutable: isExecutable,
    )
  }

  /// A file that is there, taken away. `expected` is what it held when this was planned.
  static func delete(
    _ path: WorkspacePath,
    expected: [UInt8]? = nil,
  ) -> FileChange {
    FileChange(
      action: .delete,
      path: path,
      expected: expected,
    )
  }
}

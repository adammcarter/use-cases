@testable import UseCasesCore

/// A change written the way a test reads it.
struct PlannedChange {
  let action: FileChangeAction
  let path: String
  let text: String
  var isExecutable = false

  static func create(
    _ path: String,
    _ text: String = "",
  ) -> PlannedChange {
    PlannedChange(
      action: .create,
      path: path,
      text: text,
    )
  }

  static func createExecutable(
    _ path: String,
    _ text: String = "",
  ) -> PlannedChange {
    PlannedChange(
      action: .create,
      path: path,
      text: text,
      isExecutable: true,
    )
  }

  static func replace(
    _ path: String,
    _ text: String = "",
  ) -> PlannedChange {
    PlannedChange(
      action: .replace,
      path: path,
      text: text,
    )
  }

  static func delete(_ path: String) -> PlannedChange {
    PlannedChange(
      action: .delete,
      path: path,
      text: "",
    )
  }
}

extension WritePlan {
  /// A plan of the changes, in the order given.
  static func making(_ changes: [PlannedChange]) throws -> WritePlan {
    try WritePlan(
      changes: changes.map { change in
        try FileChange(
          action: change.action,
          path: WorkspacePath(validating: change.path),
          bytes: Array(change.text.utf8),
          isExecutable: change.isExecutable,
        )
      },
    )
  }
}

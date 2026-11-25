import UseCasesCore

/// Why a plan was refused or could not be written.
enum PlannedWriteError: Error, Equatable {
  /// The plan is in conflict with what is there: a file to create that exists, a file to replace
  /// that does not, a file where a folder is needed.
  case conflicting(PlanWritingError)

  /// The workspace as the plan would leave it is INVALID, or its links cannot be known.
  case leavesInvalid(LinkedWorkspaceError)

  /// The workspace as the plan would leave it is not what the change meant: the plan is refused,
  /// and the words say how it differs.
  case diverges(String)

  /// The checked plan could not be written.
  case writing(PlanWritingError)
}

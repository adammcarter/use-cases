/// Why a plan could not be applied. Every refusal that can be known before the first byte is
/// found before it, so a refused plan writes nothing.
public enum PlanWritingError: Error, Equatable, Sendable {
  /// A file the plan would create is already there.
  case exists(path: String)

  /// A file the plan would replace or delete is not there, or is not a file.
  case missing(path: String)

  /// A file the plan would replace or delete holds something else than it did when the plan was
  /// made: someone changed it in between, and writing the plan would lose that change.
  case changed(path: String)

  /// Something that is not a folder stands where the plan needs a folder.
  case obstructed(
    path: String,
    reason: String,
  )

  /// The system would not let a file or folder be written.
  case unwritable(
    location: String,
    reason: String,
  )

  /// The failure as one line a person reads.
  public var message: String {
    switch self {
    case let .exists(path):
      "\(path) already exists, so it is not overwritten"
    case let .missing(path):
      "\(path) is not a file here"
    case let .changed(path):
      "\(path) changed since it was read; run it again"
    case let .obstructed(path, reason):
      "\(path) cannot be used: \(reason)"
    case let .unwritable(location, reason):
      "\(location) cannot be written: \(reason)"
    }
  }
}

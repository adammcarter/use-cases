/// Why a verdict was not recorded (chapter 13 §12, chapter 16 §12).
public enum RecordingError: Error, Equatable, Sendable {
  /// The status is not one the store keeps.
  case unknownStatus(String)

  /// The use case is neither an id nor the start of one.
  case noUseCase(String)

  /// The use case is the start of several ids and none of them is exactly it.
  case ambiguousUseCase(
    String,
    matching: [String],
  )

  /// The use case has no such route.
  case noRoute(
    useCase: String,
    route: String,
  )

  /// The route is the start of several routes of the use case and none of them is exactly it.
  case ambiguousRoute(
    useCase: String,
    route: String,
    matching: [String],
  )

  /// The use case is a DRAFT, so nothing can be verified against it yet. `missing` says what
  /// is left to write.
  case draft(
    useCase: String,
    missing: [String],
  )

  /// Fingerprinting found that the workspace is INVALID. Each problem is one line.
  case invalidWorkspace(problems: [String])

  /// The route has no fingerprint, which a route of a READY use case in a valid workspace
  /// always has.
  case noFingerprint(
    useCase: String,
    route: String,
  )

  /// An attachment is not there.
  case attachmentMissing(String)

  /// An attachment is a folder.
  case attachmentIsFolder(String)

  /// An attachment is something that is neither a regular file nor a folder: a pipe, a device.
  case attachmentNotRegular(String)

  /// An attachment is there and could not be read.
  case attachmentUnreadable(
    path: String,
    reason: String,
  )

  /// Two attachments would be shown by one name.
  case duplicateAttachmentName(String)

  /// No use case is READY, so there is nothing to offer.
  case noReadyUseCase

  /// The results store could not be written, so nothing was recorded.
  case storage(String)

  /// The refusal as the text a person reads.
  public var message: String {
    switch self {
    case let .unknownStatus(status):
      "status must be one of pass, fail, incomplete, error; not '\(status)'"
    case let .noUseCase(target):
      "no use case or id prefix '\(target)' in this workspace"
    case let .ambiguousUseCase(target, matching):
      "'\(target)' could be any of \(matching.joined(separator: ", ")); name one in full"
    case let .noRoute(useCase, route):
      "no route \(useCase) / \(route)"
    case let .ambiguousRoute(useCase, route, matching):
      "'\(route)' could be any route of \(useCase): \(matching.joined(separator: ", "))"
    case let .draft(useCase, missing):
      "\(useCase) is DRAFT, so it cannot be verified yet; "
        + "missing \(missing.joined(separator: ", "))"
    case let .invalidWorkspace(problems):
      problems.joined(separator: "\n")
    case let .noFingerprint(useCase, route):
      "route \(route) of \(useCase) has no fingerprint"
    case let .attachmentMissing(path):
      "attachment \(path) does not exist"
    case let .attachmentIsFolder(path):
      "attachment \(path) is a folder; attach files"
    case let .attachmentNotRegular(path):
      "attachment \(path) is not a regular file"
    case let .attachmentUnreadable(path, reason):
      "attachment \(path) cannot be read: \(reason)"
    case let .duplicateAttachmentName(name):
      "two attachments are named '\(name)'; names must be unique within a result"
    case .noReadyUseCase:
      "no READY use case to record a verdict for"
    case let .storage(message):
      message
    }
  }
}

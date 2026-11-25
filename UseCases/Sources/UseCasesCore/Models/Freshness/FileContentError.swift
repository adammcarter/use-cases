/// Why a file's bytes could not be read for fingerprinting.
enum FileContentError: Error, Equatable, Sendable {
  /// Nothing is there any more.
  case missing

  /// A folder, or a pipe, socket or device, which is never opened.
  case notAFile(FileEntryKind)

  /// The system refused.
  case unreadable(FileSystemError)

  /// The file was written to while it was read, so what was read is not one state of it.
  case changedWhileRead
}

extension FileContentError {
  /// How a failure to read a file shows: a file that went since it was looked at is missing.
  init(reading error: FileSystemError) {
    if case .notFound = error {
      self = .missing
    } else {
      self = .unreadable(error)
    }
  }
}

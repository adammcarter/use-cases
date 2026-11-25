/// Why a file given as an attachment could not be read.
enum AttachmentReadingError: Error, Equatable, Sendable {
  /// Nothing is there.
  case missing

  /// A folder is there.
  case folder

  /// Something is there that is neither a regular file nor a folder: a pipe, a device, a socket.
  /// It is never opened, because reading a pipe can block forever.
  case notRegular

  /// The file is there and the system would not let it be read.
  case unreadable(String)
}

extension AttachmentReadingError {
  /// How a failure to read the rest of a file that was opened shows.
  init(reading error: FileSystemError) {
    switch error {
    case .notFound:
      self = .missing
    case let .unreadable(_, reason):
      self = .unreadable(reason)
    case .notUTF8:
      self = .unreadable(error.description)
    }
  }
}

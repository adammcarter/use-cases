import Foundation

/// Why a file or folder could not be read.
enum FileSystemError: Error, Equatable, Sendable {
  /// Nothing is there.
  case notFound(URL)

  /// It is there but cannot be read (permissions, not a folder, not a file, and so on).
  case unreadable(URL, reason: String)

  /// The file is not valid UTF-8 text.
  case notUTF8(URL)
}

extension FileSystemError: CustomStringConvertible {
  var description: String {
    switch self {
    case let .notFound(url):
      "'\(url.path)' does not exist"
    case let .unreadable(url, reason):
      "'\(url.path)' cannot be read: \(reason)"
    case let .notUTF8(url):
      "'\(url.path)' is not valid UTF-8 text"
    }
  }
}

import Foundation

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

/// Opens attachments on the machine's file system with POSIX calls.
struct LocalAttachmentReader: AttachmentReading {
  func chunks(of file: URL) throws(AttachmentReadingError) -> any FileChunkReading {
    var status = stat()

    guard stat(file.path, &status) == 0 else {
      let failure = errno

      guard failure == ENOENT || failure == ENOTDIR else {
        throw .unreadable(Self.reason(failure))
      }

      throw .missing
    }

    switch status.st_mode & S_IFMT {
    case S_IFREG:
      break
    case S_IFDIR:
      throw .folder
    default:
      throw .notRegular
    }

    do {
      return try PosixChunkReader(opening: file)
    } catch {
      throw AttachmentReadingError(reading: error)
    }
  }

  private static func reason(_ errorNumber: Int32) -> String {
    String(cString: strerror(errorNumber))
  }
}

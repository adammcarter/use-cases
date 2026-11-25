import Foundation

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

/// A regular file opened with POSIX calls and read a chunk at a time. It follows a symlink as
/// `readBytes` does, and it closes the file when it is let go of.
final class PosixChunkReader: FileChunkReading {
  let length: Int

  private let file: URL
  private let descriptor: Int32

  /// Opens the file.
  ///
  /// - Throws: ``FileSystemError/notFound(_:)`` when nothing is there, and
  ///   ``FileSystemError/unreadable(_:reason:)`` for anything else that stops the file being read.
  init(opening file: URL) throws(FileSystemError) {
    let descriptor = open(
      file.path,
      O_RDONLY | O_CLOEXEC,
    )
    guard descriptor >= 0 else {
      let failure = errno

      throw Self.error(
        at: file,
        errorNumber: failure,
      )
    }

    var status = stat()

    guard fstat(descriptor, &status) == 0 else {
      let failure = errno
      close(descriptor)

      throw Self.error(
        at: file,
        errorNumber: failure,
      )
    }
    guard status.st_mode & S_IFMT == S_IFREG else {
      close(descriptor)

      throw .unreadable(
        file,
        reason: "it is not a regular file",
      )
    }

    self.file = file
    self.descriptor = descriptor
    length = Int(status.st_size)
  }

  deinit {
    close(descriptor)
  }

  func nextChunk() throws(FileSystemError) -> [UInt8] {
    var chunk = [UInt8](
      repeating: 0,
      count: FileChunk.size,
    )

    while true {
      let count = chunk.withUnsafeMutableBytes { buffer in
        read(descriptor, buffer.baseAddress, buffer.count)
      }

      if count < 0 {
        guard errno == EINTR else {
          throw Self.error(
            at: file,
            errorNumber: errno,
          )
        }
        continue
      }

      chunk.removeSubrange(count...)

      return chunk
    }
  }

  private static func error(
    at file: URL,
    errorNumber: Int32,
  ) -> FileSystemError {
    if errorNumber == ENOENT || errorNumber == ENOTDIR {
      return .notFound(file)
    }

    return .unreadable(
      file,
      reason: String(cString: strerror(errorNumber)),
    )
  }
}

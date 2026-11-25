import Foundation

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

extension LocalStoreFileWriter {
  func stageFile(
    copying source: any FileChunkReading,
    in folder: URL,
  ) throws(StoreWritingError) -> URL {
    let staged = folder.appendingPathComponent(".staged.tmp-\(UUID().uuidString)")
    let descriptor = open(
      staged.path,
      O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC,
      Self.filePermissions,
    )
    guard descriptor >= 0 else {
      throw Self.error(
        at: staged,
        errorNumber: errno,
      )
    }

    defer {
      close(descriptor)
    }

    do throws(StoreWritingError) {
      while true {
        let chunk: [UInt8]

        do throws(FileSystemError) {
          chunk = try source.nextChunk()
        } catch {
          throw StoreWritingError.unwritable(
            location: staged.path,
            reason: "what it is to hold cannot be read: \(error)",
          )
        }

        guard !chunk.isEmpty else {
          break
        }

        try Self.writeAll(
          chunk,
          to: descriptor,
          at: staged,
        )
      }

      try Self.flush(
        descriptor,
        at: staged,
      )
    } catch {
      discard(staged)

      throw error
    }

    return staged
  }

  func publishStagedFile(
    _ staged: URL,
    at file: URL,
  ) throws(StoreWritingError) {
    // `link` fails when the name is taken, which `rename` would silently overwrite.
    guard link(staged.path, file.path) == 0 else {
      let failure = errno
      discard(staged)

      throw Self.error(
        at: file,
        errorNumber: failure,
      )
    }

    discard(staged)
    try flushFolder(at: file.deletingLastPathComponent())
  }
}

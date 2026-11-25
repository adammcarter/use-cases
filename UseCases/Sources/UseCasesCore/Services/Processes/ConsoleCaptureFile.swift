import Foundation

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

/// The scratch file a command's stdout and stderr are written to (chapter 14 §10). It is a file,
/// never a pipe, so a command that leaves a background process holding its output open cannot
/// hold the run up, and a command never blocks on a full pipe. The file has no name: it is
/// removed the moment it is made.
struct ConsoleCaptureFile: ConsoleCapturing {
  /// The most that is kept from each end of a larger capture: 512 KiB.
  static let keptEachEnd = 512 * 1024

  /// Open for reading and writing, close-on-exec, and never 0, 1 or 2.
  let descriptor: Int32

  /// Makes an empty capture in the system's temporary folder.
  static func create() throws(ProcessSupervisingError) -> ConsoleCaptureFile {
    let path = FileManager.default.temporaryDirectory
      .appendingPathComponent("use-cases-console-\(UUID().uuidString)").path

    let opened = open(
      path,
      O_RDWR | O_CREAT | O_EXCL | O_CLOEXEC,
      0o600,
    )

    guard opened >= 0 else {
      throw .captureUnavailable(reason: String(cString: strerror(errno)))
    }

    unlink(path)

    // The command's own 0, 1 and 2 are set up for it; the capture must be none of them.
    guard opened < 3 else {
      return ConsoleCaptureFile(descriptor: opened)
    }

    let moved = fcntl(opened, F_DUPFD_CLOEXEC, 3)
    let failure = errno
    close(opened)

    guard moved >= 0 else {
      throw .captureUnavailable(reason: String(cString: strerror(failure)))
    }

    return ConsoleCaptureFile(descriptor: moved)
  }

  func release() {
    close(descriptor)
  }

  /// What was written: all of it up to 1 MiB, else the first and last 512 KiB around a marker
  /// saying how many bytes were not kept. Each end is decoded on its own, so a character cut at
  /// the edge of a kept end becomes U+FFFD and does not disturb the other end.
  func read() throws(ProcessSupervisingError) -> ProcessConsole {
    var information = stat()

    guard fstat(descriptor, &information) == 0 else {
      throw .captureUnavailable(reason: String(cString: strerror(errno)))
    }

    let size = Int(information.st_size)
    let half = Self.keptEachEnd

    guard size > 2 * half else {
      return try ProcessConsole(
        text: bytes(count: size, at: 0).lossyUTF8Text,
        omittedByteCount: 0,
      )
    }

    let first = try bytes(count: half, at: 0)
    let last = try bytes(count: half, at: size - half)
    let omitted = size - 2 * half

    return ProcessConsole(
      text: first.lossyUTF8Text
        + "\n[... \(omitted) bytes not kept ...]\n"
        + last.lossyUTF8Text,
      omittedByteCount: omitted,
    )
  }

  /// `count` bytes from `offset`, read with `pread` so the position the command is writing at
  /// is never touched.
  func bytes(
    count: Int,
    at offset: Int,
  ) throws(ProcessSupervisingError) -> [UInt8] {
    var buffer = [UInt8](repeating: 0, count: count)
    var filled = 0

    while filled < count {
      let received = buffer.withUnsafeMutableBytes { target in
        pread(
          descriptor,
          target.baseAddress?.advanced(by: filled),
          count - filled,
          off_t(offset + filled),
        )
      }

      if received < 0 {
        guard errno == EINTR else {
          throw .captureUnavailable(reason: String(cString: strerror(errno)))
        }

        continue
      }

      // The file ended early: the command truncated its own output. Keep what is there.
      guard received > 0 else {
        break
      }

      filled += received
    }

    return Array(buffer[0 ..< filled])
  }
}

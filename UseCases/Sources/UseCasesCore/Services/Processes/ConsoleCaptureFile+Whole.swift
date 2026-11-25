import Foundation

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

extension ConsoleCaptureFile {
  /// Everything written so far, with nothing left out however large, decoded as UTF-8 with
  /// U+FFFD for each invalid sequence. For a caller that hands the output on whole, as against
  /// ``read()``, which keeps the most a console is shown.
  func readEverything() throws(ProcessSupervisingError) -> String {
    var information = stat()

    guard fstat(descriptor, &information) == 0 else {
      throw .captureUnavailable(reason: String(cString: strerror(errno)))
    }

    return try bytes(
      count: Int(information.st_size),
      at: 0,
    ).lossyUTF8Text
  }

  /// Writes `text` into an empty capture and rewinds it, so a command given the capture as its
  /// stdin reads the text from the start.
  func fill(with text: String) throws(ProcessSupervisingError) {
    var remaining = Array(text.utf8)[...]

    while !remaining.isEmpty {
      let written = remaining.withUnsafeBytes { source in
        write(descriptor, source.baseAddress, source.count)
      }

      if written < 0 {
        guard errno == EINTR else {
          throw .captureUnavailable(reason: String(cString: strerror(errno)))
        }

        continue
      }

      remaining = remaining.dropFirst(written)
    }

    guard lseek(descriptor, 0, SEEK_SET) == 0 else {
      throw .captureUnavailable(reason: String(cString: strerror(errno)))
    }
  }
}

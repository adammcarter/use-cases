import Foundation

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

/// The thread every command the server starts hangs by (chapter 20): a pipe the server holds the
/// write end of open for as long as it lives, and never writes to. Each command is handed the
/// read end. When the server dies, killed outright included, the pipe reaches its end and the
/// commands cancel themselves, so that none of them goes on after the server that started it.
struct ServerLifeline: Sendable {
  /// The read end, which each command is handed.
  let readEnd: Int32

  private let writeEnd: Int32

  /// Makes the pipe. Neither end is inherited by a program started without being handed it.
  init() throws(ToolServerError) {
    var ends: [Int32] = [-1, -1]

    guard pipe(&ends) == 0 else {
      throw .lifeline(reason: String(cString: strerror(errno)))
    }

    // Moved out of the way of the descriptors a program is handed (0 to 3), and closed on exec.
    guard let reading = Self.moved(ends[0]) else {
      let reason = String(cString: strerror(errno))
      Foundation.close(ends[1])

      throw .lifeline(reason: reason)
    }

    guard let writing = Self.moved(ends[1]) else {
      let reason = String(cString: strerror(errno))
      Foundation.close(reading)

      throw .lifeline(reason: reason)
    }

    readEnd = reading
    writeEnd = writing
  }

  /// Lets go of the pipe. The commands still running reach its end: they are cancelled by now.
  func close() {
    Foundation.close(readEnd)
    Foundation.close(writeEnd)
  }

  private static func moved(_ descriptor: Int32) -> Int32? {
    let moved = fcntl(descriptor, F_DUPFD_CLOEXEC, 10)
    Foundation.close(descriptor)

    return moved < 0 ? nil : moved
  }
}

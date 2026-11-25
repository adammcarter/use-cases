import Foundation

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

/// Asks the system whether a child has ended, without waiting for it.
struct ProcessReaper: ProcessReaping {
  func poll(_ processIdentifier: pid_t) async throws(ProcessSupervisingError)
    -> ProcessTermination?
  {
    var status: Int32 = 0

    while true {
      let answered = waitpid(
        processIdentifier,
        &status,
        WNOHANG,
      )

      if answered == processIdentifier {
        return Self.termination(of: status)
      }

      if answered == 0 {
        return nil
      }

      guard errno == EINTR else {
        throw .waitFailed(reason: String(cString: strerror(errno)))
      }
    }
  }

  /// Reads a wait status the way `WIFEXITED` and `WIFSIGNALED` do, which are macros Swift cannot
  /// call. The low seven bits are 0 for an exit, whose code is the next byte, and otherwise the
  /// signal that killed the child.
  private static func termination(of status: Int32) -> ProcessTermination {
    let signal = status & 0x7F

    guard signal != 0 else {
      return .exited((status >> 8) & 0xFF)
    }

    return .signaled(signal)
  }
}

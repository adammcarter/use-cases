import Foundation

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

/// The thread a `use-cases` hangs by when another program started it: the read end of a pipe whose
/// other end that program holds open for as long as it lives (chapter 20). Nothing is ever written
/// to it. When the program dies, whichever way, the pipe reaches its end, and the `use-cases` that
/// holds the read end cancels exactly as it would if it were told to (chapter 13 §15): a write
/// that has begun finishes, a run seals as cancelled, the tests it started are stopped.
struct ProcessLifeline: Sendable {
  /// The environment variable that names the descriptor.
  static let variable = "USE_CASES_LIFELINE_FD"

  /// The descriptor a started program is handed the lifeline as, whatever it was in the program
  /// that started it.
  static let descriptor: Int32 = 3

  private let number: Int32

  /// The lifeline this process was started with, if it was: read once, and taken out of the
  /// environment so that the tests and tools it starts do not take it for theirs.
  static let inherited: ProcessLifeline? = {
    let lifeline = ProcessLifeline(environment: ProcessInfo.processInfo.environment)
    unsetenv(variable)

    return lifeline
  }()

  /// The lifeline `environment` names, if it names a pipe that is open.
  init?(environment: [String: String]) {
    guard
      let text = environment[Self.variable],
      let number = Int32(text),
      number >= 0
    else {
      return nil
    }

    self.init(descriptor: number)
  }

  /// The lifeline that is descriptor `descriptor`, if that is a pipe that is open.
  init?(descriptor: Int32) {
    var information = stat()

    guard
      fstat(descriptor, &information) == 0,
      information.st_mode & S_IFMT == S_IFIFO
    else {
      return nil
    }

    number = descriptor
  }

  /// Whether the program that started this one is gone: the pipe has reached its end.
  var isBroken: Bool {
    var watched = pollfd(
      fd: number,
      events: Int16(POLLIN),
      revents: 0,
    )

    guard poll(&watched, 1, 0) > 0 else {
      return false
    }

    return watched.revents & Int16(POLLHUP | POLLERR) != 0
  }
}

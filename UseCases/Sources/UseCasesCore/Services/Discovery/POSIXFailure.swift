import Foundation

/// A system call that failed, with the `errno` it left.
struct POSIXFailure: Error, Equatable {
  let code: Int32

  /// What the system says went wrong.
  var reason: String {
    String(cString: strerror(code))
  }
}

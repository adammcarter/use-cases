import Foundation
@testable import UseCasesCore

/// A preflight that notes the path of each change it is asked about, on a stream, and refuses
/// every change with the error it was given, or none.
struct SpyChangeChecking: ChangeChecking {
  /// The paths asked about, in order, until ``asked()``.
  let paths: AsyncStream<String>

  private let noting: AsyncStream<String>.Continuation
  private let refusal: PlanWritingError?

  /// - Parameter refusal: What every change is refused with; `nil` lets every change through.
  init(refusing refusal: PlanWritingError? = nil) {
    (paths, noting) = AsyncStream.makeStream(of: String.self)
    self.refusal = refusal
  }

  /// Every path asked about so far.
  func asked() async -> [String] {
    noting.finish()

    var found: [String] = []

    for await path in paths {
      found.append(path)
    }

    return found
  }

  func check(
    _ change: FileChange,
    in root: URL,
  ) throws(PlanWritingError) {
    noting.yield(change.path)

    if let refusal {
      throw refusal
    }
  }
}

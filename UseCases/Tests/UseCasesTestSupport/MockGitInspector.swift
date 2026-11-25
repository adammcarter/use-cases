import Foundation
import UseCasesCore

/// A clone the test decides: where its work tree and hooks are, or why git cannot say.
public struct MockGitInspector: GitInspecting {
  private let answer: Result<GitLocation, HooksError>

  /// A clone with this work tree and hooks folder.
  public init(location: GitLocation) {
    answer = .success(location)
  }

  /// A folder git refuses, or git that cannot be run.
  public init(failing error: HooksError) {
    answer = .failure(error)
  }

  public func locate(from folder: URL) async throws(HooksError) -> GitLocation {
    try answer.get()
  }
}

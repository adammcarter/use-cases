import Foundation
import UseCasesCore

/// A locator that says the running executable is where the test decides, or nowhere.
public struct MockRunningExecutableLocating: RunningExecutableLocating {
  private let location: URL?

  /// Says the executable is at `location`, or cannot be found when it is `nil`.
  public init(at location: URL?) {
    self.location = location
  }

  public func executableLocation() -> URL? {
    location
  }
}

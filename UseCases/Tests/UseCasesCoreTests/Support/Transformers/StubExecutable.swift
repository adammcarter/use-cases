import Foundation
@testable import UseCasesCore

/// A running executable that is wherever the test says.
struct StubExecutable: RunningExecutableLocating {
  let location: URL?

  func executableLocation() -> URL? {
    location
  }
}

import Foundation
@testable import UseCasesCore

extension DiscoveryContext {
  /// A context for a test folder that excludes nothing.
  static func excludingNothing(in directory: TemporaryDirectory) -> DiscoveryContext {
    DiscoveryContext(
      rootDirectory: directory.url,
      builtInExcludes: [],
      configuredExcludes: [],
    )
  }
}

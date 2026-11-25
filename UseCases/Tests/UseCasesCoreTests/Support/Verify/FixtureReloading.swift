import Foundation
@testable import UseCasesCore

/// Reads the fixture's workspace again, as the command line does at the finish point, after doing
/// what the test wants to happen while the reports were read.
struct FixtureReloading: WorkspaceReloading {
  let workspace: URL
  let whileReading: @Sendable () -> Void
  let failure: ReloadingError?

  init(
    _ fixture: VerifyFixture,
    failure: ReloadingError? = nil,
    whileReading: @escaping @Sendable () -> Void = {},
  ) {
    workspace = fixture.workspace
    self.failure = failure
    self.whileReading = whileReading
  }

  func reload() async throws(ReloadingError) -> ResolvedWorkspace {
    whileReading()

    if let failure {
      throw failure
    }

    do {
      let loaded = try WorkspaceLoader().load(from: .workspace(workspace))

      return ResolvedWorkspace(
        workspace: loaded,
        links: LinkResolver().resolveLinks(in: loaded),
      )
    } catch {
      throw .invalid(problems: ["\(error)"])
    }
  }
}

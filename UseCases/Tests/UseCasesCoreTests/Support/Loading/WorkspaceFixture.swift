import Foundation
@testable import UseCasesCore

/// A workspace on disk, loaded by the real loader.
struct WorkspaceFixture {
  let directory: TemporaryDirectory

  init(rootConfiguration: String = YAMLSamples.root) throws {
    directory = try TemporaryDirectory()
    try directory.write("use-cases.yml", rootConfiguration)
  }

  func write(
    _ path: String,
    _ text: String,
  ) throws {
    try directory.write(path, text)
  }

  func load(
    from start: WorkspaceStart? = nil,
    using loader: WorkspaceLoader = WorkspaceLoader(),
  ) throws(WorkspaceLoadingError) -> LoadedWorkspace {
    try loader.load(from: start ?? .workspace(directory.url))
  }

  /// The loaded workspace, or a failure of the test when it is INVALID.
  func loaded() throws -> LoadedWorkspace {
    do {
      return try load()
    } catch {
      throw LoadFailure(message: error.message)
    }
  }

  /// The problem lines of an INVALID workspace, those that wait for the links to be resolved
  /// included, as `validate` raises them; empty when the workspace is valid.
  func problemsIncludingLinks(from start: WorkspaceStart? = nil) -> [String] {
    do {
      return try LinkResolver().resolveLinks(
        in: load(from: start),
        including: .none,
      ).problems
    } catch {
      return problems(of: error)
    }
  }

  /// The problem lines of an INVALID workspace; empty when it loads.
  func problems(from start: WorkspaceStart? = nil) -> [String] {
    do {
      _ = try load(from: start)
      return []
    } catch {
      return problems(of: error)
    }
  }

  private func problems(of error: WorkspaceLoadingError) -> [String] {
    switch error {
    case let .invalid(problems):
      problems
    case let .noWorkspace(message), let .schemasUnavailable(message):
      [message]
    }
  }
}

/// A workspace that was expected to load and did not.
struct LoadFailure: Error, CustomStringConvertible {
  let message: String

  var description: String {
    message
  }
}

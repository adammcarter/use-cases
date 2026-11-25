import Foundation
@testable import UseCasesCore

/// A workspace on disk plus the discoverer that reads it through the mock settings reader.
struct DiscoveryFixture {
  let directory: TemporaryDirectory
  private let fileSystem: any FileSystemReading

  init(
    fileSystem: any FileSystemReading = LocalFileSystem(),
    rootConfiguration: String = "root: true\n",
  ) throws {
    directory = try TemporaryDirectory()
    self.fileSystem = fileSystem
    try directory.write("use-cases.yml", rootConfiguration)
  }

  /// Adds a child scope's `use-cases.yml`.
  func scope(
    _ folder: String,
    _ configuration: String = "",
  ) throws {
    try directory.write("\(folder)/use-cases.yml", configuration)
  }

  var settingsLoader: any ScopeSettingsLoading {
    ScopeSettingsLoader(
      fileSystem: fileSystem,
      settingsReader: MockScopeSettingsReader(),
    )
  }

  func discover() throws -> WorkspaceDiscovery {
    let root = try RootFinder(
      fileSystem: fileSystem,
      settingsLoader: settingsLoader,
    ).requireRoot(at: directory.url)

    return WorkspaceDiscoverer(
      fileSystem: fileSystem,
      settingsLoader: settingsLoader,
    ).discover(root: root)
  }
}

extension WorkspacePath {
  /// A path written in a test.
  static func at(_ text: String) throws -> WorkspacePath {
    try WorkspacePath(validating: text)
  }
}

extension WorkspaceDiscovery {
  /// The definition files of each scope, as text, keyed by the scope's folder.
  var definitionTexts: [String: [String]] {
    var result: [String: [String]] = [:]

    for scope in scopeTree.scopes {
      result[scope.directory.text] = scope.definitionFiles.map(\.text)
    }

    return result
  }

  /// The diagnostics as `<file>: <code>`, in report order.
  var diagnosticSummaries: [String] {
    diagnostics.map { diagnostic in
      "\(diagnostic.file): \(diagnostic.code)"
    }
  }
}

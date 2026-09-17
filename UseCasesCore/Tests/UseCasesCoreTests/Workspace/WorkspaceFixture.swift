import Foundation
import Testing
import TestSupport
@testable import UseCasesCore

/// Real directories and real config files for the roots tests.
///
/// Resolving roots is filesystem work, so nothing here is mocked: every test
/// writes a `use-cases.yml` into a real temporary directory and reads the
/// answer back (see `swift-test-writing`).
enum WorkspaceFixture {
  /// A schema-valid `use-cases.yml`. Every key the schema REQUIRES is written,
  /// because a config that fails validation never reaches the code under test.
  static func configuration(
    dataRoot: String = ".",
    useCasesDirectory: String = "use-cases",
    componentIdentifier: String = "fixture",
    extra: String = "",
  ) -> String {
    """
    schema_version: 1
    workspace_id: fixture
    component_id: \(componentIdentifier)
    data_root: \(dataRoot)
    use_cases_dir: \(useCasesDirectory)
    evidence_dir: evidence
    demo_capsules_dir: demo-capsules
    showcase_runs_dir: showcase-runs
    \(extra)
    """
  }

  /// The registry the resolver validates configs against. Read from the
  /// committed files so a roots failure is never an embedding failure.
  static func registry() throws -> SchemaRegistry {
    try SchemaFixtures.registry()
  }

  /// `path` with its symlinks resolved, computed by the C library rather than
  /// by the code under test.
  static func realPath(_ path: String) -> String {
    guard let resolved = realpath(path, nil) else {
      return path
    }
    defer {
      free(resolved)
    }
    return String(cString: resolved)
  }
}

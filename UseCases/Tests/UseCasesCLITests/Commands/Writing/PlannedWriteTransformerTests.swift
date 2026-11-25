import Foundation
import Testing
import UseCasesCore

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif
@testable import UseCasesCLI

/// A links transformer runs while a change is checked, as it runs for `validate`: in the real
/// folder, never in a copy of it.
struct PlannedWriteTransformerTests {
  private let workspace: LinksWorkspace

  init() throws {
    workspace = try LinksWorkspace()
    try workspace.folder.writeProgram(
      "tools/links",
      "pwd -P > ran-in.txt\n"
        + "printf '%s' '{\"contract\":1,\"links\":[],\"diagnostics\":[]}' > \"$3\"\n",
    )
    try workspace.folder.write(
      "use-cases-bridge.yml",
      "schema_version: 1\nlinks:\n  - transformer: tools/links\n",
    )
    try workspace.folder.write(".git/HEAD", "x")
  }

  private func files() throws -> [String: String] {
    var found: [String: String] = [:]
    let walker = FileManager.default.enumerator(atPath: workspace.folder.url.path)

    while let path = walker?.nextObject() as? String {
      var isFolder: ObjCBool = false
      let location = workspace.folder.url.appendingPathComponent(path).path

      if FileManager.default.fileExists(atPath: location, isDirectory: &isFolder),
         !isFolder.boolValue
      {
        found[path] = try String(contentsOfFile: location, encoding: .utf8)
      }
    }

    return found
  }

  @Test
  func `a dry run runs the transformer in the real folder and changes no other file`()
    async throws
  {
    _ = await workspace.run(["validate"])
    let afterValidate = try files()

    let result = await workspace.run(["init", "--no-input", "--dry-run"])

    #expect(result.exitCode == 0)
    #expect(try files() == afterValidate)
    #expect(
      try workspace.read("ran-in.txt").trimmingCharacters(in: .whitespacesAndNewlines)
        == realPath,
    )
  }

  private var realPath: String {
    guard let resolved = realpath(workspace.folder.url.path, nil) else {
      return workspace.folder.url.path
    }

    defer {
      free(resolved)
    }

    return String(cString: resolved)
  }
}

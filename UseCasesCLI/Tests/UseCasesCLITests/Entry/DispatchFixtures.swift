import Foundation
import Testing
import TestSupport
import UseCasesCore

/// The dispatch corpus, and the real sandboxes each case is rebuilt in.
///
/// Recorded paths are placeholders; they are swapped for this run's sandbox,
/// working directory and repository before comparing.
enum DispatchFixtures {
  static let corpus: Result<JSONValue, SchemaError> = {
    do throws(SchemaError) {
      return try .success(JSONParser.parse(DispatchGoldenCorpus.json))
    } catch {
      return .failure(error)
    }
  }()

  /// The repository root: this file sits four directories below it.
  static var repositoryRoot: String {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .path
  }

  static func testCase(_ name: String) throws -> JSONValue {
    let cases = try #require(corpus.get()["cases"]?.arrayValue)
    return try #require(cases.first { $0["name"]?.stringValue == name }, "no case \(name)")
  }

  /// One case's sandbox, holding the files it held when it was recorded.
  struct Sandbox {
    let directory: TemporaryDirectory
    let recorded: JSONValue

    init(recorded: JSONValue) throws {
      directory = try TemporaryDirectory()
      self.recorded = recorded
      for pair in try #require(recorded["files"]?.objectValue).pairs {
        try directory.writeFile(pair.key, contents: pair.value.stringValue ?? "")
      }
    }

    var arguments: [String] {
      (recorded["args"]?.arrayValue ?? []).compactMap { argument in
        argument.stringValue.map(substituted)
      }
    }

    var expectedStatus: Int32 {
      Int32(recorded["status"]?.numberValue ?? -1)
    }

    var expectedConfiguration: String? {
      recorded["config_after"]?.stringValue
    }

    func expected(_ key: String) -> String {
      substituted(recorded[key]?.stringValue ?? "")
    }

    func configurationAfter() -> String? {
      let path = sandboxPath + "/use-cases.yml"
      return try? String(contentsOfFile: path, encoding: .utf8)
    }

    /// The sandbox as `realpath(3)` spells it, which is what the TypeScript
    /// recorded and what the CLI resolves.
    var sandboxPath: String {
      realpathOf(directory.url.path)
    }

    private func realpathOf(_ path: String) -> String {
      guard let resolved = realpath(path, nil) else {
        return path
      }
      defer {
        free(resolved)
      }
      return String(cString: resolved)
    }

    private func substituted(_ text: String) -> String {
      text
        .replacingOccurrences(of: "$SANDBOX", with: sandboxPath)
        .replacingOccurrences(of: "$CWD", with: FileManager.default.currentDirectoryPath)
        .replacingOccurrences(of: "$REPO", with: DispatchFixtures.repositoryRoot)
    }
  }
}

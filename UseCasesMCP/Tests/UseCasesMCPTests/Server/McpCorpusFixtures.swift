import Foundation
import Testing
import TestSupport
import UseCasesCore
import UseCasesMCP

/// The MCP corpus, and the real sandboxes each case is replayed in.
///
/// Recorded paths are placeholders; they are swapped for this run's sandbox
/// before comparing, so the corpus does not depend on where either side ran.
enum McpCorpusFixtures {
  static let corpus: Result<JSONValue, SchemaError> = {
    do throws(SchemaError) {
      return try .success(JSONParser.parse(McpGoldenCorpus.json))
    } catch {
      return .failure(error)
    }
  }()

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

    /// The sandbox as `realpath(3)` spells it, which is what the TypeScript
    /// recorded and what the server resolves.
    var path: String {
      guard let resolved = realpath(directory.url.path, nil) else {
        return directory.url.path
      }
      defer {
        free(resolved)
      }
      return String(cString: resolved)
    }

    /// The environment the server was started with, and the sandbox as its
    /// working directory — a relative `repo` resolves against it.
    var environment: McpEnvironment {
      var variables: [String: String] = [:]
      for pair in recorded["env"]?.objectValue?.pairs ?? [] {
        variables[pair.key] = withSandbox(pair.value.stringValue ?? "")
      }
      return McpEnvironment(variables: variables, workingDirectory: path)
    }

    var requests: [String] {
      (recorded["requests"]?.arrayValue ?? []).compactMap { line in
        line.stringValue.map(withSandbox)
      }
    }

    /// The recorded responses, `nil` where the server answered with silence.
    var responses: [String?] {
      (recorded["responses"]?.arrayValue ?? []).map { line in
        line.stringValue
      }
    }

    /// The files whose contents were recorded after the run; a value of null
    /// means the file was not there.
    var filesAfter: [(path: String, contents: String?)] {
      (recorded["files_after"]?.objectValue?.pairs ?? []).map { pair in
        (pair.key, pair.value.stringValue)
      }
    }

    /// The fields this case cannot pin, so the clock is normalised for them
    /// and only them.
    var clockFields: [String] {
      (recorded["clock_fields"]?.arrayValue ?? []).compactMap(\.stringValue)
    }

    var expectedListing: [String] {
      (recorded["workspace_listing"]?.arrayValue ?? []).compactMap(\.stringValue)
    }

    func contents(of relativePath: String) -> String? {
      try? String(contentsOfFile: path + "/" + relativePath, encoding: .utf8)
    }

    /// Every file in the sandbox now, so a read can be proved not to have
    /// written.
    func listing() -> [String] {
      let root = path
      guard let walker = FileManager.default.enumerator(atPath: root) else {
        return []
      }
      var found: [String] = []
      for case let entry as String in walker {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
          atPath: root + "/" + entry,
          isDirectory: &isDirectory,
        ), !isDirectory.boolValue
        else {
          continue
        }
        found.append(entry)
      }
      return found.sorted()
    }

    func withSandbox(_ text: String) -> String {
      text.replacingOccurrences(of: "$SANDBOX", with: path)
    }

    /// The reverse: this run's sandbox put back as the placeholder, so the
    /// produced bytes can be compared to the recorded ones directly.
    func withPlaceholder(_ text: String) -> String {
      text.replacingOccurrences(of: path, with: "$SANDBOX")
    }
  }
}

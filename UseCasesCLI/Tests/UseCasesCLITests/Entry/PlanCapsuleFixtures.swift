import Foundation
import Testing
import TestSupport
import UseCasesCore
@testable import UseCasesCLI

/// The plan- and capsule-command corpus, and the real sandboxes each case is
/// replayed in.
///
/// A sandbox is a temporary directory holding `demo-repo` (the workspace),
/// `outside` and `home`, as the generator's was. Every CLI step runs with
/// exactly PATH and HOME, as it did when the corpus was recorded.
enum PlanCapsuleFixtures {
  static let corpus: Result<JSONValue, SchemaError> = {
    do throws(SchemaError) {
      return try .success(JSONParser.parse(PlanCapsuleGoldenCorpus.json))
    } catch {
      return .failure(error)
    }
  }()

  static func testCase(_ name: String) throws -> JSONValue {
    let cases = try #require(corpus.get()["cases"]?.arrayValue)
    return try #require(cases.first { $0["name"]?.stringValue == name }, "no case \(name)")
  }

  /// One CLI step as replayed: the argv it ran and what it produced.
  struct Run {
    let arguments: [String]
    let standardOutput: String
    let standardError: String
    let exitCode: Int32
  }

  /// One case's sandbox, built from its recorded setup.
  struct Sandbox {
    let directory: TemporaryDirectory
    let recorded: JSONValue
    let root: String

    init(recorded: JSONValue) throws {
      directory = try TemporaryDirectory()
      self.recorded = recorded
      root = SandboxTree.realpathOf(directory.url.path)
      _ = try directory.makeDirectory("outside")
      _ = try directory.makeDirectory("home")
      _ = try directory.makeDirectory("demo-repo")
      for file in recorded["setup"]?["files"]?.arrayValue ?? [] {
        try directory.writeFile(
          #require(file["path"]?.stringValue),
          contents: #require(file["content"]?.stringValue),
        )
      }
    }

    var sandboxPath: String {
      root + "/demo-repo"
    }

    /// Every step in order; the CLI steps' results in order.
    func replay() async throws -> [Run] {
      var runs: [Run] = []
      for step in recorded["steps"]?.arrayValue ?? [] {
        switch step["kind"]?.stringValue {
        case "uc":
          await runs.append(runCommand(step))
        case "write":
          try directory.writeFile(
            #require(step["path"]?.stringValue),
            contents: #require(step["content"]?.stringValue),
          )
        case "chmod":
          let path = try root + "/" + #require(step["path"]?.stringValue)
          let mode = try #require(step["mode"]?.numberValue)
          try #require(chmod(path, mode_t(mode)) == 0, "chmod \(path)")
        default:
          Issue.record("unknown step \(step)")
        }
      }
      return runs
    }

    func expectedRun(_ index: Int) throws -> JSONValue {
      try #require(recorded["runs"]?.arrayValue?[index])
    }

    func expected(
      _ key: String,
      ofRun index: Int,
    ) throws -> String {
      try PlanCapsuleMasking.masked(substituted(expectedRun(index)[key]?.stringValue ?? ""))
    }

    /// The recorded tree, placeholders filled in and masked, as wire JSON.
    func expectedTree() throws -> String {
      let entries = try #require(recorded["tree_after"]?.arrayValue)
      return Self.encoded(entries.compactMap(\.objectValue).map { fields in
        var fields = fields
        if let content = fields["content"]?.stringValue {
          fields["content"] = .string(substituted(content))
        }
        return fields
      })
    }

    /// This run's tree as wire JSON, masked the same way.
    func actualTree() throws -> String {
      let listing = try JSONParser.parse(SandboxTree.listing(root: root))
      return Self.encoded(listing.arrayValue?.compactMap(\.objectValue) ?? [])
    }

    /// Each entry's path and contents masked on their own, then sorted by the
    /// masked path and encoded: masking the encoded listing instead would miss
    /// the JSON escaping a file's contents pick up inside it, and a masked
    /// path can order differently from the recorded one.
    private static func encoded(_ entries: [JSONObject]) -> String {
      let masked = entries.map { fields -> (path: String, value: JSONValue) in
        var fields = fields
        let path = PlanCapsuleMasking.masked(fields["path"]?.stringValue ?? "")
        fields["path"] = .string(path)
        if let content = fields["content"]?.stringValue {
          fields["content"] = .string(PlanCapsuleMasking.masked(content))
        }
        return (path, .object(fields))
      }
      .sorted { left, right in
        left.path.utf16.lexicographicallyPrecedes(right.path.utf16)
      }
      return JSONWriter.encode(.array(masked.map(\.value)))
    }

    private func runCommand(_ step: JSONValue) async -> Run {
      var arguments: [String] = []
      for argument in step["args"]?.arrayValue ?? [] {
        if let text = argument.stringValue {
          arguments.append(substituted(text))
        }
      }
      let environment = [
        "PATH": ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin",
        "HOME": root + "/home",
      ]
      let outcome = await CommandLineInterface.run(arguments: arguments, environment: environment)
      return Run(
        arguments: arguments,
        standardOutput: PlanCapsuleMasking.masked(outcome.standardOutput),
        standardError: PlanCapsuleMasking.masked(outcome.standardError),
        exitCode: outcome.exitCode,
      )
    }

    private func substituted(_ text: String) -> String {
      text
        .replacingOccurrences(of: "$SANDBOX", with: sandboxPath)
        .replacingOccurrences(of: "$ROOT", with: root)
        .replacingOccurrences(of: "$CWD", with: FileManager.default.currentDirectoryPath)
        .replacingOccurrences(of: "$REPO", with: DispatchFixtures.repositoryRoot)
    }
  }
}

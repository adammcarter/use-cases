import Foundation
import Testing
import TestSupport
import UseCasesCore
@testable import UseCasesCLI

/// The evidence-command corpus, and the real sandboxes each case is replayed in.
///
/// A sandbox is a temporary directory holding `demo-repo` (the workspace),
/// `outside` and `home`, as the generator's was. Every CLI step runs with
/// exactly PATH and HOME, as it did when the corpus was recorded.
enum EvidenceCommandsFixtures {
  static let corpus: Result<JSONValue, SchemaError> = {
    do throws(SchemaError) {
      return try .success(JSONParser.parse(EvidenceCommandsGoldenCorpus.json))
    } catch {
      return .failure(error)
    }
  }()

  static func testCase(_ name: String) throws -> JSONValue {
    let cases = try #require(corpus.get()["cases"]?.arrayValue)
    return try #require(cases.first { $0["name"]?.stringValue == name }, "no case \(name)")
  }

  /// One CLI step as replayed: the argv it ran and what it produced, event ids
  /// already numbered.
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
    var numbering = EvidenceEventNumbering()

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
    mutating func replay() async throws -> [Run] {
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
        case "append_ledger":
          try appendLedger(step)
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
      try EvidenceCommandsMasking.masked(substituted(expectedRun(index)[key]?.stringValue ?? ""))
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

    /// This run's tree with its event ids numbered — paths, then contents, in
    /// listing order — sorted again by numbered path, and masked, as wire JSON.
    mutating func actualTree() throws -> String {
      let listing = try JSONParser.parse(SandboxTree.listing(root: root))
      var entries: [(path: String, value: JSONObject)] = []
      for entry in listing.arrayValue ?? [] {
        guard var fields = entry.objectValue, let path = fields["path"]?.stringValue else {
          continue
        }
        let numberedPath = numbering.numbered(path)
        fields["path"] = .string(numberedPath)
        if let content = fields["content"]?.stringValue {
          fields["content"] = .string(numbering.numbered(content))
        }
        entries.append((numberedPath, fields))
      }
      entries.sort { left, right in
        left.path.utf16.lexicographicallyPrecedes(right.path.utf16)
      }
      return Self.encoded(entries.map(\.value))
    }

    /// Each entry with its own contents masked, then the wire JSON: masking
    /// the encoded listing instead would miss the JSON escaping a file's
    /// contents pick up inside it.
    private static func encoded(_ entries: [JSONObject]) -> String {
      JSONWriter.encode(.array(entries.map { fields in
        var fields = fields
        if let content = fields["content"]?.stringValue {
          fields["content"] = .string(EvidenceCommandsMasking.masked(content))
        }
        return .object(fields)
      }))
    }

    private mutating func runCommand(_ step: JSONValue) async -> Run {
      var arguments: [String] = []
      for argument in step["args"]?.arrayValue ?? [] {
        if let text = argument.stringValue {
          arguments.append(numbering.concrete(substituted(text)))
        }
      }
      let environment = [
        "PATH": ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin",
        "HOME": root + "/home",
      ]
      let outcome = await CommandLineInterface.run(arguments: arguments, environment: environment)
      let standardOutput = numbering.numbered(outcome.standardOutput)
      let standardError = numbering.numbered(outcome.standardError)
      return Run(
        arguments: arguments,
        standardOutput: EvidenceCommandsMasking.masked(standardOutput),
        standardError: EvidenceCommandsMasking.masked(standardError),
        exitCode: outcome.exitCode,
      )
    }

    private func appendLedger(_ step: JSONValue) throws {
      let identifier = try numbering.concrete(#require(step["evidence"]?.stringValue))
      let content = try numbering.concrete(#require(step["content"]?.stringValue))
      let prefix = String(identifier.utf16.prefix(2)) ?? ""
      let path = "\(sandboxPath)/evidence/by-id/\(prefix)/\(identifier).jsonl"
      let handle = try #require(FileHandle(forWritingAtPath: path), "no ledger at \(path)")
      defer {
        try? handle.close()
      }
      try handle.seekToEnd()
      try handle.write(contentsOf: Data(content.utf8))
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

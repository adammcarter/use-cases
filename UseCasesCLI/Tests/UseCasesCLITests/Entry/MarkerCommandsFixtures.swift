import Foundation
import Testing
import TestSupport
import UseCasesCore
@testable import UseCasesCLI

/// The marker-command corpus, and the real sandboxes each case is replayed in.
///
/// A sandbox is a temporary directory holding `demo-repo` (the workspace),
/// `outside` and `home`, as the generator's was. Every CLI step runs with
/// exactly PATH, HOME, git's global and system configuration off and the
/// step's own variables, as it did when the corpus was recorded.
enum MarkerCommandsFixtures {
  static let corpus: Result<JSONValue, SchemaError> = {
    do throws(SchemaError) {
      return try .success(JSONParser.parse(MarkerCommandsGoldenCorpus.json))
    } catch {
      return .failure(error)
    }
  }()

  /// What git commits with, so a commit is the same commit every time.
  static let gitIdentity = [
    "GIT_AUTHOR_NAME": "Probe",
    "GIT_AUTHOR_EMAIL": "probe@example.invalid",
    "GIT_AUTHOR_DATE": "2026-01-01T00:00:00Z",
    "GIT_COMMITTER_NAME": "Probe",
    "GIT_COMMITTER_EMAIL": "probe@example.invalid",
    "GIT_COMMITTER_DATE": "2026-01-01T00:00:00Z",
  ]

  static func testCase(_ name: String) throws -> JSONValue {
    let cases = try #require(corpus.get()["cases"]?.arrayValue)
    return try #require(cases.first { $0["name"]?.stringValue == name }, "no case \(name)")
  }

  /// One CLI step as replayed: the argv it ran and what it produced.
  struct Run {
    let arguments: [String]
    let outcome: CliOutcome
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
      let setup = try #require(recorded["setup"])

      _ = try directory.makeDirectory("outside")
      _ = try directory.makeDirectory("home")
      _ = try directory.makeDirectory("demo-repo")
      if setup["git"]?.boolValue == true {
        try git(["init", "-q"])
      }
      for file in setup["files"]?.arrayValue ?? [] {
        try directory.writeFile(
          #require(file["path"]?.stringValue),
          contents: #require(file["content"]?.stringValue),
        )
      }
    }

    var sandboxPath: String {
      root + "/demo-repo"
    }

    /// Whether a run attestation can differ between two runs: a run key is
    /// minted (none seeded, or `UC_RUN_KEY_FILE` names a new one), or a record
    /// is dated by the wall clock because a step gives no `--generated-at`.
    var attestationsVary: Bool {
      let files = recorded["setup"]?["files"]?.arrayValue ?? []
      let seedsNoKey = files.contains { file in
        file["path"]?.stringValue == "home/.use-cases/run-key" && file["content"]?.stringValue == ""
      }
      let steps = (recorded["steps"]?.arrayValue ?? []).filter { step in
        step["kind"]?.stringValue == "uc"
      }
      let namesKeyFile = steps.contains { step in
        step["env"]?["UC_RUN_KEY_FILE"] != nil
      }
      let undated = steps.contains { step in
        let arguments = (step["args"]?.arrayValue ?? []).compactMap(\.stringValue)
        return ["verify", "recover"].contains(arguments.first ?? "")
          && !arguments.contains("--generated-at")
      }
      return seedsNoKey || namesKeyFile || undated
    }

    /// Whether any step runs keygen, whose minted PEMs are masked wherever
    /// they land.
    var runsKeygen: Bool {
      (recorded["steps"]?.arrayValue ?? []).contains { step in
        step["kind"]?.stringValue == "uc"
          && step["args"]?.arrayValue?.first?.stringValue == "keygen"
      }
    }

    /// PATH, HOME and git isolation: all a recorded run was given.
    var baseEnvironment: [String: String] {
      [
        "PATH": ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin",
        "HOME": root + "/home",
        "GIT_CONFIG_GLOBAL": "/dev/null",
        "GIT_CONFIG_NOSYSTEM": "1",
      ]
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
        case "edit":
          let path = try root + "/" + #require(step["path"]?.stringValue)
          let before = try NodeFile.readText(atPath: path)
          let after = try before.replacingOccurrences(
            of: #require(step["from"]?.stringValue),
            with: #require(step["to"]?.stringValue),
          )
          try NodeFile.writeText(after, atPath: path)
        case "remove":
          let path = try root + "/" + #require(step["path"]?.stringValue)
          try FileManager.default.removeItem(atPath: path)
        case "git":
          try git((step["args"]?.arrayValue ?? []).compactMap(\.stringValue))
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
      try substituted(expectedRun(index)[key]?.stringValue ?? "")
    }

    /// The recorded tree, placeholders filled in and masked, as wire JSON.
    func expectedTree() throws -> String {
      let recordedTree = try JSONWriter.encode(#require(recorded["tree_after"]))
      return try maskedTree(JSONParser.parse(substituted(recordedTree)))
    }

    /// This run's tree, masked, as wire JSON.
    func actualTree() throws -> String {
      try maskedTree(JSONParser.parse(SandboxTree.listing(root: root)))
    }

    func git(_ arguments: [String]) throws {
      let environment = baseEnvironment.merging(MarkerCommandsFixtures.gitIdentity) { _, identity in
        identity
      }
      let outcome = ScaffoldGitProcessRunner(environment: environment)
        .run(arguments, workingDirectory: sandboxPath)
      try #require(outcome.exitStatus == 0, "git \(arguments) failed")
    }

    private func runCommand(_ step: JSONValue) async -> Run {
      let arguments = (step["args"]?.arrayValue ?? []).compactMap { argument in
        argument.stringValue.map(substituted)
      }
      var environment = baseEnvironment
      let extra = step["env"]?.objectValue ?? JSONObject()
      for key in extra.keys {
        environment[key] = extra[key]?.stringValue.map(substituted)
      }
      let outcome = await CommandLineInterface.run(arguments: arguments, environment: environment)
      return Run(arguments: arguments, outcome: outcome)
    }

    private func maskedTree(_ tree: JSONValue) -> String {
      let entries = (tree.arrayValue ?? []).map { entry -> JSONValue in
        guard var fields = entry.objectValue, let path = fields["path"]?.stringValue,
              let content = fields["content"]?.stringValue
        else {
          return entry
        }
        var masked = MarkerCommandsMasking.masked(
          content,
          format: .file,
          attestationsVary: attestationsVary,
        )
        if runsKeygen {
          masked = MarkerCommandsMasking.withoutMintedKeys(masked)
        }
        if attestationsVary, path.hasSuffix("run-key") {
          masked = "<minted run key>"
        }
        fields["content"] = .string(masked)
        return .object(fields)
      }
      return JSONWriter.encode(.array(entries))
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

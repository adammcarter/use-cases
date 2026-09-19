import Foundation
import Testing
import TestSupport
import UseCasesCore
@testable import UseCasesCLI

/// The showcase- and approve-run corpus, and the real sandboxes each case is
/// replayed in.
///
/// A sandbox is a temporary directory holding `demo-repo` (the workspace),
/// `outside` and `home`, as the generator's was. Every CLI step runs with
/// exactly PATH and HOME plus whatever variable its own step named, as it did
/// when the corpus was recorded. A `keys` step mints this replay's OWN ed25519
/// pair, so no key material is shared with the recording — which is why
/// ``ShowcaseCommandsMasking`` masks every PEM body and signature.
enum ShowcaseCommandsFixtures {
  static let corpus: Result<JSONValue, SchemaError> = {
    do throws(SchemaError) {
      return try .success(JSONParser.parse(ShowcaseCommandsGoldenCorpus.json))
    } catch {
      return .failure(error)
    }
  }()

  static func testCase(_ name: String) throws -> JSONValue {
    let cases = try #require(corpus.get()["cases"]?.arrayValue)
    return try #require(cases.first { $0["name"]?.stringValue == name }, "no case \(name)")
  }

  /// One CLI step as replayed: the argv it ran and what it produced, masked
  /// for comparison and raw for a `capture` step — a minted approval request
  /// must be signed as it really was, nonce and all.
  struct Run {
    let arguments: [String]
    let standardOutput: String
    let standardError: String
    let rawStandardOutput: String
    let exitCode: Int32
  }

  /// One case's sandbox, built from its recorded setup.
  struct Sandbox {
    let directory: TemporaryDirectory
    let recorded: JSONValue
    let root: String
    /// Variables a `key_env` step added to every later run.
    var extraEnvironment: [String: String] = [:]

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
        case "chmod":
          let path = try root + "/" + #require(step["path"]?.stringValue)
          let mode = try #require(step["mode"]?.numberValue)
          try #require(chmod(path, mode_t(mode)) == 0, "chmod \(path)")
        case "keys":
          try mintKeys(step)
        case "capture":
          let captured = try #require(runs.last, "capture before any run")
          try directory.writeFile(
            #require(step["path"]?.stringValue),
            contents: captured.rawStandardOutput,
          )
        case "key_env":
          let path = try root + "/" + #require(step["path"]?.stringValue)
          try extraEnvironment[#require(step["variable"]?.stringValue)] =
            try String(contentsOfFile: path, encoding: .utf8)
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
      try ShowcaseCommandsMasking.masked(substituted(expectedRun(index)[key]?.stringValue ?? ""))
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

    /// Each entry's contents masked on its own, then the wire JSON: masking
    /// the encoded listing instead would miss the JSON escaping a file's
    /// contents pick up inside it.
    private static func encoded(_ entries: [JSONObject]) -> String {
      JSONWriter.encode(.array(entries.map { fields in
        var fields = fields
        if let content = fields["content"]?.stringValue {
          fields["content"] = .string(ShowcaseCommandsMasking.masked(content))
        }
        return .object(fields)
      }))
    }

    /// This replay's own ed25519 pair, and the keyring naming its public half,
    /// written exactly where and how the generator wrote its own (the private
    /// key 0600, the keyring two-space JSON with a trailing newline).
    private func mintKeys(_ step: JSONValue) throws {
      let keypair = SigningKeyGeneration.generate()
      let privatePath = try root + "/" + #require(step["privatePath"]?.stringValue)
      try NodeFile.writeText(keypair.privatePEM, atPath: privatePath, mode: 0o600)
      try directory.writeFile(
        #require(step["publicPath"]?.stringValue),
        contents: keypair.publicPEM,
      )
      try directory.writeFile(
        #require(step["keyringPath"]?.stringValue),
        contents: Self.keyring(
          keyIdentifier: #require(step["keyId"]?.stringValue),
          publicPEM: keypair.publicPEM,
        ),
      )
    }

    /// `JSON.stringify(keyring, null, 2)` with a trailing newline, as the
    /// generator wrote it.
    private static func keyring(
      keyIdentifier: String,
      publicPEM: String,
    ) -> String {
      let escaped = publicPEM.replacingOccurrences(of: "\n", with: "\\n")
      return """
      {
        "keyring_schema_id": "ucase-public-key-registry-v1",
        "keys": [
          {
            "key_id": "\(keyIdentifier)",
            "algorithm": "ed25519",
            "public_key": "\(escaped)",
            "valid_from": "2026-01-01T00:00:00Z",
            "valid_until": null,
            "status": "active",
            "max_assurance_tier": "trusted_host_user_presence"
          }
        ]
      }

      """
    }

    private func runCommand(_ step: JSONValue) async -> Run {
      var arguments: [String] = []
      for argument in step["args"]?.arrayValue ?? [] {
        if let text = argument.stringValue {
          arguments.append(substituted(text))
        }
      }
      var environment = [
        "PATH": ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin",
        "HOME": root + "/home",
      ]
      for (name, value) in step["env"]?.objectValue?.pairs ?? [] {
        environment[name] = value.stringValue
      }
      environment.merge(extraEnvironment) { _, added in
        added
      }
      let outcome = await CommandLineInterface.run(arguments: arguments, environment: environment)
      return Run(
        arguments: arguments,
        standardOutput: ShowcaseCommandsMasking.masked(outcome.standardOutput),
        standardError: ShowcaseCommandsMasking.masked(outcome.standardError),
        rawStandardOutput: outcome.standardOutput,
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

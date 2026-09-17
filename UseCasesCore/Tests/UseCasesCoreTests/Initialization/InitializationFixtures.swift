import Foundation
import Testing
import TestSupport
@testable import UseCasesCore

/// The init corpus, and the real sandboxes each case is rebuilt in.
///
/// A sandbox holds the repository directory and an `outside` directory, as the
/// generator's did. git runs with global and system configuration switched off,
/// as it did when the corpus was recorded.
enum InitializationFixtures {
  static let corpus: Result<JSONValue, SchemaError> = {
    do throws(SchemaError) {
      return try .success(JSONParser.parse(InitializationGoldenCorpus.json))
    } catch {
      return .failure(error)
    }
  }()

  static let today = "2026-09-17"

  /// The process environment with git's global and system configuration off.
  static var isolatedEnvironment: [String: String] {
    var environment = ProcessInfo.processInfo.environment
    environment["GIT_CONFIG_GLOBAL"] = "/dev/null"
    environment["GIT_CONFIG_NOSYSTEM"] = "1"
    return environment
  }

  static var isolatedGit: ScaffoldGitProcessRunner {
    ScaffoldGitProcessRunner(environment: isolatedEnvironment)
  }

  static func testCase(_ name: String) throws -> JSONValue {
    let cases = try #require(corpus.get()["cases"]?.arrayValue)
    return try #require(cases.first { $0["name"]?.stringValue == name }, "no init case \(name)")
  }

  static func wire(_ value: JSONValue?) -> String {
    guard let value else {
      return "<absent>"
    }
    return JSONWriter.encode(value)
  }

  /// A sandbox built from a case's `setup`.
  struct Sandbox {
    let directory: TemporaryDirectory
    let repositoryRoot: String

    init(setup: JSONValue) throws {
      directory = try TemporaryDirectory()
      let repository = try #require(setup["repository"]?.stringValue)
      // Built as a string and made with mkdir(2): URL and FileManager hand the
      // filesystem a decomposed spelling of a non-ASCII name, node does not.
      repositoryRoot = directory.url.path + "/" + repository
      _ = try directory.makeDirectory("outside")
      if setup["create_repository"]?.boolValue != false {
        try #require(mkdir(repositoryRoot, 0o777) == 0)
      }
      if setup["git"]?.boolValue == true {
        try git(["init", "-q"])
      }
      if let hooksPath = setup["hooks_path"]?.stringValue {
        try git([
          "config",
          "core.hooksPath",
          hooksPath.replacingOccurrences(of: "<repo>", with: repositoryRoot),
        ])
      }
      for directoryPath in setup["directories"]?.arrayValue ?? [] {
        _ = try directory.makeDirectory(#require(directoryPath.stringValue))
      }
      for file in setup["files"]?.arrayValue ?? [] {
        let url = try directory.writeFile(
          #require(file["path"]?.stringValue),
          contents: #require(file["content"]?.stringValue),
        )
        if let mode = file["mode"]?.numberValue {
          try #require(chmod(url.path, mode_t(mode)) == 0)
        }
      }
      for link in setup["symlinks"]?.arrayValue ?? [] {
        let url = try directory.url.appendingPathComponent(#require(link["path"]?.stringValue))
        try FileManager.default.createDirectory(
          at: url.deletingLastPathComponent(),
          withIntermediateDirectories: true,
        )
        try FileManager.default.createSymbolicLink(
          atPath: url.path,
          withDestinationPath: #require(link["target"]?.stringValue),
        )
      }
    }

    func git(_ arguments: [String]) throws {
      let outcome = InitializationFixtures.isolatedGit.run(
        arguments,
        workingDirectory: repositoryRoot,
      )
      try #require(outcome.exitStatus == 0, "git \(arguments) failed")
    }

    /// core.hooksPath as git reports it, or nil when git reports none.
    func configuredHooksPath() -> String? {
      let outcome = InitializationFixtures.isolatedGit.run(
        ["config", "--get", "core.hooksPath"],
        workingDirectory: repositoryRoot,
      )
      guard outcome.exitStatus == 0 else {
        return nil
      }
      return outcome.standardOutput.replacingOccurrences(of: repositoryRoot, with: "<repo>")
    }

    /// Every entry under the sandbox except `.git` directories, in code-unit
    /// order, as the generator lists them.
    func tree() throws -> JSONValue {
      var entries: [(path: String, value: JSONValue)] = []
      try walk("", into: &entries)
      entries.sort { left, right in
        left.path.utf16.lexicographicallyPrecedes(right.path.utf16)
      }
      return .array(entries.map(\.value))
    }

    /// readdir(3)'s names, exactly as stored.
    private static func names(in directory: String) throws -> [String] {
      let stream = try #require(opendir(directory))
      defer {
        closedir(stream)
      }
      var names: [String] = []
      while let entry = readdir(stream) {
        let name = withUnsafeBytes(of: entry.pointee.d_name) { raw in
          UTF8Text.decodeReplacingInvalid(Array(raw.prefix { $0 != 0 }))
        }
        if name != ".", name != ".." {
          names.append(name)
        }
      }
      return names
    }

    private func walk(
      _ relativeDirectory: String,
      into entries: inout [(path: String, value: JSONValue)],
    ) throws {
      let root = directory.url.path
      let absoluteDirectory = relativeDirectory.isEmpty ? root : root + "/" + relativeDirectory
      for name in try Self.names(in: absoluteDirectory) where name != ".git" {
        let path = relativeDirectory.isEmpty ? name : relativeDirectory + "/" + name
        let absolutePath = root + "/" + path
        var status = stat()
        try #require(lstat(absolutePath, &status) == 0)
        switch status.st_mode & S_IFMT {
        case S_IFLNK:
          let target = try FileManager.default.destinationOfSymbolicLink(atPath: absolutePath)
          entries.append((path, .object(JSONObject([
            ("path", .string(path)),
            ("kind", .string("symlink")),
            ("target", .string(target)),
          ]))))
        case S_IFDIR:
          entries.append((path, .object(JSONObject([
            ("path", .string(path)),
            ("kind", .string("directory")),
          ]))))
          try walk(path, into: &entries)
        default:
          let bytes = try #require(FileManager.default.contents(atPath: absolutePath))
          entries.append((path, .object(JSONObject([
            ("path", .string(path)),
            ("kind", .string("file")),
            ("mode", .string(String(status.st_mode & 0o777, radix: 8))),
            ("content", .string(UTF8Text.decodeReplacingInvalid([UInt8](bytes)))),
          ]))))
        }
      }
    }
  }
}

/// A clock stopped at one instant.
struct FixedInitializationClock: InitializationClock {
  let milliseconds: Double

  func now() -> Double {
    milliseconds
  }
}

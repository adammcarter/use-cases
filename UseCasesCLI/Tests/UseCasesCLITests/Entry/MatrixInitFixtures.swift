import Foundation
import Testing
import TestSupport
import UseCasesCore

/// The matrix and init corpus, and the real sandboxes each case is rebuilt in.
///
/// A sandbox is a temporary directory holding `demo-repo` and `outside`, as the
/// generator's was. git runs with global and system configuration switched
/// off, as it did when the corpus was recorded.
enum MatrixInitFixtures {
  static let corpus: Result<JSONValue, SchemaError> = {
    do throws(SchemaError) {
      return try .success(JSONParser.parse(MatrixInitGoldenCorpus.json))
    } catch {
      return .failure(error)
    }
  }()

  /// Diagnostics whose message is a parser's own wording — V8's `JSON.parse`
  /// or the `yaml` package's — which the port does not reproduce: the
  /// comparison replaces it on both sides (see docs/rewrite/ladder-notes.md,
  /// row 4). Their codes, and everything else, are still compared.
  static let parserWordedCodes: Set = [
    "matrix.mutation_invalid_json",
    "parse_error",
    "evidence_parse_error",
  ]
  static let maskedMessage = "<parser message>"

  /// The process environment with git's global and system configuration off.
  static var isolatedEnvironment: [String: String] {
    var environment = ProcessInfo.processInfo.environment
    environment["GIT_CONFIG_GLOBAL"] = "/dev/null"
    environment["GIT_CONFIG_NOSYSTEM"] = "1"
    return environment
  }

  static func testCase(_ name: String) throws -> JSONValue {
    let cases = try #require(corpus.get()["cases"]?.arrayValue)
    return try #require(cases.first { $0["name"]?.stringValue == name }, "no case \(name)")
  }

  /// Whether `text` names a parser-worded code; every other output is compared
  /// raw, byte for byte.
  static func carriesParserWording(_ text: String) -> Bool {
    parserWordedCodes.contains { code in
      text.contains("\"code\":\"\(code)\"") || text.contains("\u{2717} \(code): ")
    }
  }

  /// `text` with each parser-worded diagnostic's message replaced, in either
  /// rendering.
  static func masked(_ text: String) -> String {
    if let envelope = try? JSONParser.parse(text), var object = envelope.objectValue {
      let diagnostics = (object["diagnostics"]?.arrayValue ?? []).map { diagnostic in
        guard let code = diagnostic["code"]?.stringValue, parserWordedCodes.contains(code),
              var fields = diagnostic.objectValue
        else {
          return diagnostic
        }
        fields["message"] = .string(maskedMessage)
        return JSONValue.object(fields)
      }
      object["diagnostics"] = .array(diagnostics)
      return JSONWriter.encode(.object(object)) + "\n"
    }
    let prefixes = parserWordedCodes.map { code in
      "  \u{2717} \(code): "
    }
    return text
      .split(separator: "\n", omittingEmptySubsequences: false)
      .map { line in
        let prefix = prefixes.first { candidate in
          line.hasPrefix(candidate)
        }
        return prefix.map { prefix in
          prefix + maskedMessage
        } ?? String(line)
      }
      .joined(separator: "\n")
  }

  static func wire(_ value: JSONValue?) -> String {
    guard let value else {
      return "<absent>"
    }
    return JSONWriter.encode(value)
  }

  /// One case's sandbox, built from its recorded setup.
  struct Sandbox {
    let directory: TemporaryDirectory
    let recorded: JSONValue
    let root: String

    init(recorded: JSONValue) throws {
      directory = try TemporaryDirectory()
      self.recorded = recorded
      root = Self.realpathOf(directory.url.path)
      let setup = try #require(recorded["setup"])

      _ = try directory.makeDirectory("outside")
      if setup["repository"]?.boolValue == true {
        try #require(mkdir(sandboxPath, 0o777) == 0)
      }
      if setup["git"]?.boolValue == true {
        try git(["init", "-q"])
      }
      if let hooksPath = setup["hooks_path"]?.stringValue {
        try git(["config", "core.hooksPath", hooksPath])
      }
      for directoryPath in setup["directories"]?.arrayValue ?? [] {
        _ = try directory.makeDirectory(#require(directoryPath.stringValue))
      }
      for file in setup["files"]?.arrayValue ?? [] {
        try directory.writeFile(
          #require(file["path"]?.stringValue),
          contents: #require(file["content"]?.stringValue),
        )
      }
      for link in setup["symlinks"]?.arrayValue ?? [] {
        let path = try root + "/" + #require(link["path"]?.stringValue)
        try FileManager.default.createDirectory(
          atPath: (path as NSString).deletingLastPathComponent,
          withIntermediateDirectories: true,
        )
        try FileManager.default.createSymbolicLink(
          atPath: path,
          withDestinationPath: #require(link["target"]?.stringValue),
        )
      }
    }

    var sandboxPath: String {
      root + "/demo-repo"
    }

    var arguments: [String] {
      (recorded["args"]?.arrayValue ?? []).compactMap { argument in
        argument.stringValue.map(substituted)
      }
    }

    var expectedStatus: Int32 {
      Int32(recorded["status"]?.numberValue ?? -1)
    }

    func expected(_ key: String) -> String {
      substituted(recorded[key]?.stringValue ?? "")
    }

    /// The recorded tree with its placeholders filled in for this run.
    var expectedTree: String {
      substituted(MatrixInitFixtures.wire(recorded["tree_after"]))
    }

    var expectedHooksPath: String? {
      recorded["hooks_path_after"]?.stringValue
    }

    func git(_ arguments: [String]) throws {
      let outcome = ScaffoldGitProcessRunner(environment: MatrixInitFixtures.isolatedEnvironment)
        .run(arguments, workingDirectory: sandboxPath)
      try #require(outcome.exitStatus == 0, "git \(arguments) failed")
    }

    /// core.hooksPath as git reports it, or nil when there is no repository or
    /// git reports none.
    func configuredHooksPath() -> String? {
      guard FileManager.default.fileExists(atPath: sandboxPath + "/.git") else {
        return nil
      }
      let outcome = ScaffoldGitProcessRunner(environment: MatrixInitFixtures.isolatedEnvironment)
        .run(["config", "--get", "core.hooksPath"], workingDirectory: sandboxPath)
      return outcome.exitStatus == 0 ? outcome.standardOutput : nil
    }

    /// Every entry under the sandbox except `.git` directories, in code-unit
    /// order, as the generator lists them.
    func tree() throws -> String {
      var entries: [(path: String, value: JSONValue)] = []
      try walk("", into: &entries)
      entries.sort { left, right in
        left.path.utf16.lexicographicallyPrecedes(right.path.utf16)
      }
      return MatrixInitFixtures.wire(.array(entries.map(\.value)))
    }

    private func substituted(_ text: String) -> String {
      text
        .replacingOccurrences(of: "$SANDBOX", with: sandboxPath)
        .replacingOccurrences(of: "$ROOT", with: root)
        .replacingOccurrences(of: "$CWD", with: FileManager.default.currentDirectoryPath)
        .replacingOccurrences(of: "$REPO", with: DispatchFixtures.repositoryRoot)
        .replacingOccurrences(of: "$TODAY", with: Self.today)
    }

    /// `new Date().toISOString().slice(0, 10)`.
    private static var today: String {
      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = [.withFullDate]
      formatter.timeZone = TimeZone(identifier: "UTC")
      return formatter.string(from: Date())
    }

    private static func realpathOf(_ path: String) -> String {
      guard let resolved = realpath(path, nil) else {
        return path
      }
      defer {
        free(resolved)
      }
      return String(cString: resolved)
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
          String(bytes: raw.prefix { $0 != 0 }, encoding: .utf8) ?? ""
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
          let content = try NodeFile.readText(atPath: absolutePath)
          entries.append((path, .object(JSONObject([
            ("path", .string(path)),
            ("kind", .string("file")),
            ("mode", .string(String(status.st_mode & 0o777, radix: 8))),
            ("content", .string(content)),
          ]))))
        }
      }
    }
  }
}

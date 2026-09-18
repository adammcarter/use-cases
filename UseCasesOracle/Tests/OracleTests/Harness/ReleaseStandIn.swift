import CryptoKit
import Foundation

/// A stand-in for GitHub Releases, on disk — the Swift shape of
/// `tests/helpers/release-stand-in.ts`.
///
/// `bin/use-cases-bootstrap` downloads its executable from a release, so a
/// black-box test of it needs a release. These helpers publish one into a
/// temporary directory laid out exactly as GitHub serves it
/// (`<downloads>/v<version>/<asset>`) and hand back a `file://` base URL, so the
/// suite never touches the network and never reads the developer's own cache.
///
/// No HTTP server is needed and none is started: the bootstrap fetches with
/// `curl`, which reads `file://` with the same exit codes it gives for a missing
/// remote asset (22/37 → "absent"), so the whole download path is exercised
/// against a local tree. Measured, not assumed — row 6 ran the TypeScript suite
/// this way and the port reproduces its results.
///
/// Two differences from the TypeScript, both deliberate:
///   * `scratch()` / `cleanupScratch()` are gone. Every temporary tree is a
///     `TemporaryDirectory` owned by the value that needs it, so it is removed
///     when the last reference goes — Swift Testing runs tests in parallel in
///     one process, where a module-level list of directories emptied in an
///     `afterEach` would be shared mutable state across concurrent tests.
///   * The archive's SHA256 is computed here with CryptoKit rather than by
///     shelling out to `shasum`. The oracle computing the digest itself, rather
///     than through the same tool the subject uses, is strictly the stronger
///     side of a black box.
enum ReleaseStandIn {
  /// The executables a release archive carries, and the wrappers in `bin/`.
  static let executables = ["use-cases", "use-cases-mcp"]

  /// Every platform a release publishes. Apple Silicon only from 0.8.0 (owner
  /// decision, 2026-09-17): the toolchain warns that x86_64 is deprecated for
  /// the deployment target, so the x86_64 asset was retired rather than shipped
  /// stale.
  static let publishedPlatforms = ["macos-arm64"]

  static let repositoryRoot = OracleLayout.repositoryRoot
  static let bootstrapPath = "\(OracleLayout.repositoryRoot)/bin/use-cases-bootstrap"

  /// What `uname` reports, read once — the runtime check the TypeScript makes
  /// with `platform()` and `arch()`.
  static let host: (system: String, machine: String) = {
    var info = utsname()
    guard uname(&info) == 0 else {
      return ("unknown", "unknown")
    }
    // The fields are C char arrays, which Swift imports as tuples. They must be
    // read through a pointer to the FIELD — binding one through an `Any`
    // parameter boxes a copy and reads the box, which answers an empty string
    // and silently disables every download test.
    func string<Field>(_ field: inout Field) -> String {
      withUnsafePointer(to: &field) { pointer in
        pointer.withMemoryRebound(
          to: CChar.self,
          capacity: MemoryLayout<Field>.size,
        ) { bytes in
          String(cString: bytes)
        }
      }
    }
    return (string(&info.sysname), string(&info.machine))
  }()

  /// Whether this machine can be a download target at all.
  ///
  /// `ci.yml` runs the TypeScript suite on `ubuntu-latest`, where there is no
  /// published archive and no `use-cases` to exec, so the tests that drive a
  /// real download are skipped there rather than throwing. The consequence is
  /// deliberate and worth knowing: `release.distribution.*` is provable on
  /// Apple Silicon only, so a green run on a Linux runner does not prove those
  /// four rows.
  static let canRunBootstrap = host.system == "Darwin" && host.machine == "arm64"

  /// The platform slug the bootstrap must resolve on the machine running the
  /// suite. It THROWS off Apple Silicon rather than answering a slug nothing
  /// publishes, so a download test that forgets its condition trait fails loudly
  /// instead of passing against the wrong asset.
  static func hostPlatform() throws -> String {
    guard canRunBootstrap else {
      throw StandInFailure.unsupportedHost(
        published: publishedPlatforms,
        system: host.system,
        machine: host.machine,
      )
    }
    return "macos-arm64"
  }

  /// A well-formed slug that no release publishes — what `USE_CASES_PLATFORM`
  /// is pointed at to prove the override decides the asset and is still refused.
  static func unpublishedPlatform() -> String {
    "macos-x86_64"
  }

  enum StandInFailure: Error, CustomStringConvertible {
    case unsupportedHost(published: [String], system: String, machine: String)
    case commandFailed(command: String, exitCode: Int32, standardError: String)

    var description: String {
      switch self {
      case let .unsupportedHost(published, system, machine):
        "a release publishes \(published.joined(separator: ", ")) only; " +
          "this machine is \(system)/\(machine)"
      case let .commandFailed(command, exitCode, standardError):
        "\(command) exited \(exitCode): \(standardError)"
      }
    }
  }

  /// How a published release should differ from a well-formed one.
  struct Options: Sendable {
    var version = "9.9.9-standin"
    var platform: String?
    /// Publish an archive whose bytes do not match the sums file.
    var corruptArchive = false
    /// Publish the sums file but not the archive (an asset missing from the release).
    var omitArchive = false
    /// Publish the archive but no SHA256SUMS at all.
    var omitSums = false
    /// Publish a SHA256SUMS that does not mention this asset.
    var omitSumsLine = false
    /// Leave the requested executable out of the archive.
    var omitExecutable: String?
    /// Publish executables with a body of your own instead of the default
    /// stand-in. Used to prove the `bin/` wrapper chain execs all the way
    /// through: an executable that prints its own `$$` reports the SPAWNED pid
    /// only when no shell is left holding the process.
    var executableBody: (@Sendable (String) -> String)?
  }

  /// A published release, and how to reach it. Holding the value keeps the tree
  /// on disk; dropping it removes it.
  struct Published: Sendable {
    let directory: TemporaryDirectory
    /// Local directory serving as the release downloads root.
    let downloadsRoot: String
    /// `file://` URL for `USE_CASES_RELEASE_BASE_URL`.
    let baseUrl: String
    let version: String
    let platform: String
    let assetName: String
    /// The SHA256 the sums file publishes for the asset.
    let publishedSha256: String
    /// The SHA256 of the bytes actually served (differs when `corruptArchive`).
    let servedSha256: String

    var releaseDirectory: String {
      "\(downloadsRoot)/v\(version)"
    }
  }

  /// The default stand-in executable: a shell script, not a Mach-O. The
  /// bootstrap's job is to verify and exec whatever the release published, and a
  /// script makes the test hermetic.
  static func standInExecutable(_ name: String) -> String {
    """
    #!/bin/sh
    if [ "$1" = "--fail" ]; then echo "stand-in \(name) refused" >&2; exit 3; fi
    echo "stand-in \(name) args:$*"

    """
  }

  /// Write the executables the archive will carry, and answer their names.
  static func stage(
    into root: TemporaryDirectory,
    _ options: Options,
  ) throws -> [String] {
    var members: [String] = []
    for name in executables where options.omitExecutable != name {
      let body = options.executableBody?(name) ?? standInExecutable(name)
      let staged = try root.writeFile("stage/\(name)", contents: body)
      try FileManager.default.setAttributes(
        [.posixPermissions: NSNumber(value: Int16(0o755))],
        ofItemAtPath: staged.path,
      )
      members.append(name)
    }
    return members
  }

  /// Publish a release into a temporary directory and return how to reach it.
  static func publish(_ options: Options = Options()) async throws -> Published {
    let slug = try options.platform ?? hostPlatform()
    let version = options.version
    let assetName = "use-cases-\(version)-\(slug).tar.gz"

    let root = try TemporaryDirectory("standin")
    let releaseDirectory = "downloads/v\(version)"
    try root.makeDirectory(releaseDirectory)

    let members = try stage(into: root, options)

    // Build the archive outside the release directory so `omitArchive` can
    // simply not publish it while its checksum is still what the sums file
    // claims.
    let built = "\(root.path)/\(assetName)"
    try await requireSuccess(
      executable: "/usr/bin/tar",
      arguments: ["-czf", built, "-C", "\(root.path)/stage"] + members,
    )
    let trueSha = try sha256(ofFileAt: built)

    var servedSha = trueSha
    if !options.omitArchive {
      let publishedPath = "\(root.path)/\(releaseDirectory)/\(assetName)"
      if options.corruptArchive {
        // Same name, different bytes: the mismatch the bootstrap must refuse.
        try root.writeFile(
          "\(releaseDirectory)/\(assetName)",
          contents: "this is not the archive that was checksummed\n",
        )
        servedSha = try sha256(ofFileAt: publishedPath)
      } else {
        try FileManager.default.copyItem(atPath: built, toPath: publishedPath)
      }
    }

    if !options.omitSums {
      let line = options.omitSumsLine
        ? "\(String(repeating: "0", count: 64))  some-other-asset.tar.gz"
        : "\(trueSha)  \(assetName)"
      try root.writeFile("\(releaseDirectory)/SHA256SUMS", contents: "\(line)\n")
    }

    let downloadsRoot = "\(root.path)/downloads"
    // `absoluteString` ends a directory URL with a slash; Node's `pathToFileURL`
    // does not. The bootstrap strips one trailing slash either way, but the
    // tests compare the URL it echoes back against this string, so it has to be
    // the same shape the TypeScript handed over.
    let baseUrl = URL(fileURLWithPath: downloadsRoot, isDirectory: true).absoluteString
    return Published(
      directory: root,
      downloadsRoot: downloadsRoot,
      baseUrl: baseUrl.hasSuffix("/") ? String(baseUrl.dropLast()) : baseUrl,
      version: version,
      platform: slug,
      assetName: assetName,
      publishedSha256: trueSha,
      servedSha256: servedSha,
    )
  }

  /// Which `bin/` entry to run: a wrapper name, or the bootstrap engine itself.
  enum Entry: Sendable {
    case useCases
    case useCasesMcp
    case bootstrap

    var scriptPath: String {
      switch self {
      case .useCases: "\(OracleLayout.repositoryRoot)/bin/use-cases"
      case .useCasesMcp: "\(OracleLayout.repositoryRoot)/bin/use-cases-mcp"
      case .bootstrap: ReleaseStandIn.bootstrapPath
      }
    }
  }

  /// Run a `bin/` entry with every real cache and release setting stripped, so a
  /// test can never read the network or the developer's own cache by accident.
  ///
  /// An environment value of `nil` DELETES the variable, which is how the
  /// TypeScript's `{ XDG_CACHE_HOME: undefined }` reads.
  static func run(
    entry: Entry = .useCases,
    arguments: [String] = [],
    environment: [String: String?] = [:],
    pathPrefix: String? = nil,
    executable: String? = nil,
  ) async throws -> CliBinary.Outcome {
    // A HOME nothing else shares: an unset cache override must not reach
    // ~/Library. Held until the run finishes, then removed with the value.
    let home = try TemporaryDirectory("home")
    var resolved = ProcessInfo.processInfo.environment
    for key in resolved.keys where key.hasPrefix("USE_CASES_") {
      resolved.removeValue(forKey: key)
    }
    resolved.removeValue(forKey: "XDG_CACHE_HOME")
    resolved["HOME"] = home.path
    resolved["LLVM_PROFILE_FILE"] = "/dev/null"
    for (key, value) in environment {
      if let value {
        resolved[key] = value
      } else {
        resolved.removeValue(forKey: key)
      }
    }
    if let pathPrefix {
      resolved["PATH"] = "\(pathPrefix):\(resolved["PATH"] ?? "")"
    }

    let outcome = try await OracleProcess.run(
      executable: executable ?? entry.scriptPath,
      arguments: arguments,
      cwd: OracleLayout.repositoryRoot,
      environment: resolved,
      inheritEnvironment: false,
    )
    withExtendedLifetime(home) {}
    return outcome
  }

  /// Every file under a directory, relative and sorted — for "nothing was
  /// written".
  static func fileTree(_ root: String) -> [String] {
    guard let walker = FileManager.default.enumerator(atPath: root) else {
      return []
    }
    var found: [String] = []
    for case let entry as String in walker {
      var isDirectory: ObjCBool = false
      let full = "\(root)/\(entry)"
      if FileManager.default.fileExists(atPath: full, isDirectory: &isDirectory),
         !isDirectory.boolValue
      {
        found.append(entry)
      }
    }
    return found.sorted()
  }

  /// A PATH-stub directory whose `uname` reports another operating system.
  /// The returned directory must be held for as long as the stub is needed.
  static func unameStub(
    system: String,
    machine: String,
  ) throws -> TemporaryDirectory {
    let directory = try TemporaryDirectory("uname")
    try directory.writeScript(
      "uname",
      body: """
      case "$1" in
        -m) echo "\(machine)" ;;
        *) echo "\(system)" ;;
      esac
      """,
    )
    return directory
  }

  static func sha256(ofFileAt path: String) throws -> String {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    return SHA256.hash(data: data).map { byte in
      String(format: "%02x", byte)
    }.joined()
  }

  /// Run a command that is scaffolding rather than subject: if `tar` fails the
  /// fixture is broken, and saying so beats a test failing somewhere later.
  static func requireSuccess(
    executable: String,
    arguments: [String],
  ) async throws {
    let outcome = try await OracleProcess.run(
      executable: executable,
      arguments: arguments,
      cwd: OracleLayout.repositoryRoot,
      environment: [:],
    )
    guard outcome.exitCode == 0 else {
      throw StandInFailure.commandFailed(
        command: "\(executable) \(arguments.joined(separator: " "))",
        exitCode: outcome.exitCode,
        standardError: outcome.standardError,
      )
    }
  }

  /// The mode bits of a path, for the "is it executable" assertions.
  static func permissions(of path: String) throws -> Int {
    let attributes = try FileManager.default.attributesOfItem(atPath: path)
    return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
  }

  static func setPermissions(
    _ mode: Int,
    of path: String,
  ) throws {
    try FileManager.default.setAttributes(
      [.posixPermissions: NSNumber(value: Int16(mode))],
      ofItemAtPath: path,
    )
  }

  /// The version in `.claude-plugin/plugin.json` — what the bootstrap reads when
  /// `USE_CASES_VERSION` is unset.
  static func pluginVersion() throws -> String {
    let manifest = try OracleJson.parse(
      String(
        contentsOfFile: "\(OracleLayout.repositoryRoot)/.claude-plugin/plugin.json",
        encoding: .utf8,
      ),
    )
    return manifest["version"]?.stringValue ?? ""
  }
}

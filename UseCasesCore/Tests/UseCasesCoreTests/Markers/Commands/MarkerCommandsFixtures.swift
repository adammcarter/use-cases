import Foundation
import Testing
import TestSupport
@testable import UseCasesCore

/// Access to the generated TypeScript corpus in ``MarkerCommandsGoldenCorpus``,
/// and the real temporary workspaces its cases are replayed in.
///
/// Every expected value — a result object, a file's bytes, a mode — is what the
/// TypeScript produced. Nothing expected is assembled in Swift, so a test
/// cannot agree with the implementation by sharing its mistake.
enum MarkerCommandsFixtures {
  static let corpus: Result<JSONValue, SchemaError> = {
    do throws(SchemaError) {
      return try .success(JSONParser.parse(MarkerCommandsGoldenCorpus.json))
    } catch {
      return .failure(error)
    }
  }()

  static let registry: Result<SchemaRegistry, SchemaError> = {
    do throws(SchemaError) {
      return try .success(SchemaRegistry())
    } catch {
      return .failure(error)
    }
  }()

  static func root() throws -> JSONValue {
    try corpus.get()
  }

  static func section(_ name: String) throws -> [JSONValue] {
    try #require(root()[name]?.arrayValue, "corpus has no section \(name)")
  }

  static func entry(
    _ caseName: String,
    in sectionName: String,
  ) throws -> JSONValue {
    let match = try section(sectionName).first { candidate in
      candidate["name"]?.stringValue == caseName
    }
    return try #require(match, "corpus section \(sectionName) has no case \(caseName)")
  }

  static func wire(_ value: JSONValue?) -> String {
    guard let value else {
      return "<absent>"
    }
    return JSONWriter.encode(value)
  }

  /// A temporary directory and its `realpath`, which is the spelling node's
  /// `realpathSync(mkdtempSync(...))` gave the TypeScript run.
  static func temporaryRoot() throws -> (directory: TemporaryDirectory, path: String) {
    let directory = try TemporaryDirectory()
    return try (directory, NodeFile.realPath(directory.url.path))
  }

  /// Build the entries a corpus case lists under `root`.
  static func materialize(
    _ entries: [JSONValue],
    under root: String,
  ) throws {
    for entry in entries {
      let parts = try #require(entry.arrayValue)
      let kind = try #require(parts.first?.stringValue)
      let path = try root + "/" + #require(parts[1].stringValue)
      switch kind {
      case "directory":
        try NodeFile.makeDirectories(atPath: path)
      case "file":
        try NodeFile.makeDirectories(atPath: WorkspacePath.dirname(path))
        let mode = try #require(parts[3].numberValue)
        try NodeFile.writeText(#require(parts[2].stringValue), atPath: path)
        try #require(chmod(path, mode_t(mode)) == 0)
      case "symlink":
        try NodeFile.makeDirectories(atPath: WorkspacePath.dirname(path))
        let target = try #require(parts[2].stringValue)
        try #require(symlink(target, path) == 0)
      case "chmod":
        let mode = try #require(parts[2].numberValue)
        try #require(chmod(path, mode_t(mode)) == 0)
      default:
        Issue.record("unknown entry kind \(kind)")
      }
    }
  }

  /// Undo any `chmod` entry so the temporary directory can be deleted.
  static func restorePermissions(
    _ entries: [JSONValue],
    under root: String,
  ) {
    for entry in entries {
      guard let parts = entry.arrayValue, parts.first?.stringValue == "chmod",
            let path = parts[1].stringValue
      else {
        continue
      }
      chmod(root + "/" + path, 0o755)
    }
  }

  /// Every entry under `root` as the generator's `snapshot` records it: never
  /// following a symlink, skipping `.git` internals, sorted by path with
  /// JavaScript `<`.
  static func snapshot(_ root: String) throws -> JSONValue {
    var entries: [(path: String, value: JSONValue)] = []
    try walk(root: root, relative: "", into: &entries)
    let ordered = entries.enumerated().sorted { left, right in
      if JavaScriptString.precedes(left.element.path, right.element.path) {
        return true
      }
      if JavaScriptString.precedes(right.element.path, left.element.path) {
        return false
      }
      return left.offset < right.offset
    }
    return .array(ordered.map(\.element.value))
  }

  private static func walk(
    root: String,
    relative: String,
    into entries: inout [(path: String, value: JSONValue)],
  ) throws {
    let full = relative.isEmpty ? root : root + "/" + relative
    for name in try NodeFile.directoryNames(atPath: full) {
      let childRelative = relative.isEmpty ? name : relative + "/" + name
      let childFull = root + "/" + childRelative
      var status = stat()
      try #require(lstat(childFull, &status) == 0)
      switch status.st_mode & S_IFMT {
      case S_IFLNK:
        let target = try FileManager.default.destinationOfSymbolicLink(atPath: childFull)
        entries.append((
          childRelative,
          .array([.string("symlink"), .string(childRelative), .string(target)])
        ))
      case S_IFDIR:
        guard name != ".git" else {
          continue
        }
        entries.append((childRelative, .array([.string("directory"), .string(childRelative)])))
        try walk(root: root, relative: childRelative, into: &entries)
      default:
        let contents = try NodeFile.readText(atPath: childFull)
        entries.append((childRelative, .array([
          .string("file"),
          .string(childRelative),
          .string(contents),
          .number(Double(status.st_mode & 0o7777)),
        ])))
      }
    }
  }

  static func optionalInteger(
    _ value: JSONValue,
    _ key: String,
  ) -> Int? {
    guard let number = value[key]?.numberValue else {
      return nil
    }
    return Int(number)
  }
}

/// The generator's clock and id factory: one counter shared by both, so the
/// order they are read in is part of what a case checks.
final class CommandTicks {
  private var tick = 0

  func clock() -> String {
    defer {
      tick += 1
    }
    return "2026-09-17T10:00:\(tick < 10 ? "0" : "")\(tick).000Z"
  }

  func identifier() -> String {
    defer {
      tick += 1
    }
    let digits = String(tick)
    return "event-" + String(repeating: "0", count: max(0, 4 - digits.count)) + digits
  }
}

/// git answering `show <ref>:<path>` from fixed texts keyed by the path's
/// basename, and failing as a path absent at the ref fails otherwise.
struct ScriptedGitRunner: GitRunning {
  let texts: [String: String]

  func run(
    _ arguments: [String],
    workingDirectory _: String?,
  ) throws(GitError) -> String {
    let specification = arguments.count > 1 ? arguments[1] : ""
    let base = specification.split(separator: "/", omittingEmptySubsequences: false).last
      .map(String.init) ?? ""
    if let text = texts[base] {
      return text
    }
    throw .commandFailed(
      standardError: "fatal: path '\(base)' does not exist in 'HEAD'",
      description: "scripted",
    )
  }
}

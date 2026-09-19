import Foundation
import Testing
import TestSupport
@testable import UseCasesCore

/// The capsule corpus, and the real workspaces each case is rebuilt in.
///
/// Results are compared as wire bytes with `<workspace>` put back to the
/// case's own path. A `parse_error` message is masked on both sides:
/// `JSON.parse` and the `yaml` package word their errors themselves, and that
/// wording is accepted as differing (docs/rewrite/ladder-notes.md, row 4).
enum CapsulesFixtures {
  static let corpus: Result<JSONValue, SchemaError> = {
    do throws(SchemaError) {
      return try .success(JSONParser.parse(CapsulesGoldenCorpus.json))
    } catch {
      return .failure(error)
    }
  }()

  static func testCase(
    _ name: String,
    in section: String,
  ) throws -> JSONValue {
    let cases = try #require(corpus.get()[section]?.arrayValue, "no section \(section)")
    return try #require(cases.first { $0["name"]?.stringValue == name }, "no case \(name)")
  }

  static var registry: SchemaRegistry {
    get throws {
      try UseCasesFixtures.registry.get()
    }
  }

  /// `{ result }` or `{ thrown: { code, message } }`.
  static func outcome(_ attempt: () throws(DemoCapsuleError) -> JSONValue) -> JSONValue {
    do throws(DemoCapsuleError) {
      return try .object(JSONObject([("result", attempt())]))
    } catch {
      return .object(JSONObject([("thrown", .object(JSONObject([
        ("code", .string(error.code)),
        ("message", .string(error.message)),
      ])))]))
    }
  }

  /// The two outcomes compared, parser wording masked.
  static func expectSame(
    _ actual: JSONValue,
    _ expected: JSONValue?,
    in workspace: UseCasesFixtures.Workspace,
    _ label: String,
    sourceLocation: SourceLocation = #_sourceLocation,
  ) {
    let expectedText = workspace.detokenized(wire(expected.map(masked)))
    ShowcaseFixtures.expectSameWire(
      wire(masked(actual)),
      expectedText,
      label,
      sourceLocation: sourceLocation,
    )
  }

  static func wire(_ value: JSONValue?) -> String {
    UseCasesFixtures.wire(value)
  }

  /// Every `parse_error` diagnostic's message replaced by a placeholder.
  static func masked(_ value: JSONValue) -> JSONValue {
    switch value {
    case let .array(items):
      return .array(items.map(masked))
    case let .object(object):
      var result = JSONObject()
      for member in object.pairs {
        result[member.key] = masked(member.value)
      }
      if result["code"] == .string("parse_error"), result["severity"] != nil {
        result["message"] = .string("<parser wording>")
      }
      return .object(result)
    default:
      return value
    }
  }

  /// The generator's `listTree`: every file, symlink and FIFO under `root`,
  /// each directory's names in code-unit order, directories implied.
  static func tree(_ root: String) throws -> JSONValue {
    var entries: [JSONValue] = []
    func walk(_ relativeDirectory: String) throws {
      let directory = relativeDirectory.isEmpty ? root : root + "/" + relativeDirectory
      let names = try FileManager.default.contentsOfDirectory(atPath: directory)
        .sorted(by: JavaScriptStringOrder.codeUnitAscending)
      for name in names {
        let path = relativeDirectory.isEmpty ? name : relativeDirectory + "/" + name
        let absolute = root + "/" + path
        var status = stat()
        try #require(lstat(absolute, &status) == 0)
        switch status.st_mode & S_IFMT {
        case S_IFLNK:
          let target = try FileManager.default.destinationOfSymbolicLink(atPath: absolute)
          entries.append(.object(JSONObject([
            ("path", .string(path)),
            ("symlink", .string(target)),
          ])))
        case S_IFDIR:
          try walk(path)
        case S_IFIFO:
          entries.append(.object(JSONObject([("path", .string(path)), ("fifo", .bool(true))])))
        default:
          let bytes = try #require(FileManager.default.contents(atPath: absolute))
          entries.append(.object(JSONObject([
            ("path", .string(path)),
            ("text", .string(UTF8Text.decodeReplacingInvalid([UInt8](bytes)))),
          ])))
        }
      }
    }
    try walk("")
    return .array(entries)
  }
}

/// A clock stopped at one instant.
struct FixedCapsuleClock: CapsuleClock {
  let milliseconds: Double

  func now() -> Double {
    milliseconds
  }
}

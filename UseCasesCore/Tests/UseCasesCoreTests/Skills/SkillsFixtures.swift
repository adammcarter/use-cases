import Foundation
import Testing
import TestSupport
@testable import UseCasesCore

/// The skill-asset corpus, and the real workspaces each case is rebuilt in:
/// the shipped files with the case's overlay laid over them, as the generator
/// laid it.
enum SkillsFixtures {
  static let corpus: Result<JSONValue, SchemaError> = {
    do throws(SchemaError) {
      return try .success(JSONParser.parse(SkillsGoldenCorpus.json))
    } catch {
      return .failure(error)
    }
  }()

  static func testCase(_ name: String) throws -> JSONValue {
    let cases = try #require(corpus.get()["cases"]?.arrayValue)
    return try #require(cases.first { $0["name"]?.stringValue == name }, "no case \(name)")
  }

  static func strings(_ key: String) throws -> [String] {
    try #require(corpus.get()[key]?.arrayValue).compactMap(\.stringValue)
  }

  /// A workspace holding the shipped files, overlaid: a null member deletes a
  /// shipped file, an object makes a directory, a string writes a file.
  static func workspace(overlay: JSONValue?) throws -> UseCasesFixtures.Workspace {
    var files = try #require(corpus.get()["shipped"]?.objectValue)
    for member in overlay?.objectValue?.pairs ?? [] {
      files[member.key] = member.value == .null ? nil : member.value
    }
    var tree: [JSONValue] = []
    for member in files.pairs {
      if let text = member.value.stringValue {
        tree.append(.object(JSONObject([
          ("kind", .string("file")),
          ("path", .string(member.key)),
          ("text", .string(text)),
        ])))
      } else {
        tree.append(.object(JSONObject([
          ("kind", .string("directory")),
          ("path", .string(member.key)),
        ])))
      }
    }
    return try UseCasesFixtures.Workspace(tree: .array(tree))
  }
}

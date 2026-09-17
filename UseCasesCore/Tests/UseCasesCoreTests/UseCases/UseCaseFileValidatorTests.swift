import Foundation
import Testing
import TestSupport
@testable import UseCasesCore

/// Validating one file from its raw bytes: the byte hash, fatal UTF-8 decoding
/// with the byte-order mark dropped, version dispatch, schema errors and
/// duplicate variant keys, against the TypeScript's results.
struct UseCaseFileValidatorTests {
  @Test(arguments: UseCasesGoldenCorpus.validateCaseNames)
  func `a file validates exactly as the TypeScript validated it`(caseName: String) throws {
    let testCase = try UseCasesFixtures.goldenCase(caseName, in: "validate")
    let sourcePath = testCase["path"]?.stringValue ?? "use-cases/target.yml"
    var tree: [JSONValue] = []
    if let base64 = testCase["base64"] {
      tree.append(.object(JSONObject([
        ("kind", .string("file")),
        ("path", .string(sourcePath)),
        ("base64", base64),
      ])))
    }
    if caseName == "directory_instead_of_file" {
      tree.append(.object(JSONObject([
        ("kind", .string("directory")),
        ("path", .string(sourcePath)),
      ])))
    }
    let workspace = try UseCasesFixtures.Workspace(tree: .array(tree))

    let result = try UseCaseFileValidator.validate(
      filePath: workspace.absolute(sourcePath),
      sourcePath: sourcePath,
      registry: UseCasesFixtures.registry.get(),
    )

    var file = JSONObject([
      ("path", .string(result.file.path)),
      ("status", .string(result.file.status.rawValue)),
    ])
    file["semantic_hash"] = result.file.semanticHash.map(JSONValue.string)
    file["file_hash"] = result.file.fileHash.map(JSONValue.string)
    let actual = JSONObject([
      ("file", .object(file)),
      ("diagnostics", .array(result.diagnostics.map(\.jsonValue))),
      ("candidates", .array(result.candidates.map(UseCasesFixtures.candidate))),
    ])
    try UseCasesFixtures.expectMembers(of: testCase["result"], equal: actual, in: workspace)
  }

  @Test(arguments: [
    ([UInt8](), ""),
    ([0xEF, 0xBB, 0xBF], ""),
    ([0xEF, 0xBB, 0xBF, 0xEF, 0xBB, 0xBF, 0x61], "\u{FEFF}a"),
    ([0x61, 0xEF, 0xBB, 0xBF], "a\u{FEFF}"),
    ([0x61, 0x0D, 0x0A], "a\r\n"),
  ])
  func `decoding drops one leading byte order mark and nothing else`(
    bytes: [UInt8],
    text: String,
  ) throws {
    let decoded = try #require(UseCaseFileValidator.decodeStrictly(bytes))

    #expect(Array(decoded.unicodeScalars) == Array(text.unicodeScalars))
  }

  @Test(arguments: [
    [0x80],
    [0xE2, 0x82],
    [0xC0, 0xAF],
    [0xED, 0xA0, 0x80],
    [0xF4, 0x90, 0x80, 0x80],
    [0xFF, 0xFE],
  ] as [[UInt8]])
  func `decoding refuses every ill formed sequence`(bytes: [UInt8]) {
    #expect(UseCaseFileValidator.decodeStrictly(bytes) == nil)
  }
}

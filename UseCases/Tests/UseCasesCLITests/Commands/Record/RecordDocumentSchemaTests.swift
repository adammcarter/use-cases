import Foundation
import Testing
@testable import UseCasesCLI

struct RecordDocumentSchemaTests {
  private static let schemaPath = "schemas/output/cli-record.schema.json"

  private let workspace: LinksWorkspace

  init() throws {
    workspace = try LinksWorkspace()
  }

  private func failures(of document: JSONValue) throws -> [String] {
    try PublishedSchema(path: Self.schemaPath).failures(of: document)
  }

  @Test(arguments: [
    ["--json", "record", "shop.pay.card", "unit-tests", "pass"],
    ["--json", "record", "shop.pay.card", "unit-tests", "fail", "a note"],
    ["--json", "record", "shop.pay.c", "unit-tests", "incomplete"],
    ["--json", "record", "shop.pay.card", "unit-tests", "error", "it \"broke\""],
  ])
  func `the record document of every request follows the published schema`(
    arguments: [String],
  ) async throws {
    let result = await workspace.run(arguments)

    #expect(result.exitCode == 0)
    #expect(try failures(of: result.document()) == [])
  }

  @Test
  func `the document is the sealed record run: its manifest fields and its one result`(
  ) async throws {
    let document = try await workspace.run([
      "--json",
      "record",
      "shop.pay.card",
      "unit-tests",
      "pass",
      "ok",
    ])
    .document()

    #expect(document["command"] == .string("record"))
    #expect(document["output_version"] == .integer(1))
    #expect(document["run_version"] == .integer(1))
    #expect(document["kind"] == .string("record"))
    #expect(document["sources"] == .array([]))
    #expect(document["errors"] == .array([]))
    #expect(document["diagnostics"] == .array([]))
    #expect(document["unlinked_tests"] == .array([]))
    #expect(document["notes"] == .array([]))

    guard case let .array(results)? = document["results"], let result = results.first else {
      Issue.record("no results")
      return
    }

    #expect(results.count == 1)
    #expect(result["use_case"] == .string("shop.pay.card"))
    #expect(result["route"] == .string("unit-tests"))
    #expect(result["status"] == .string("pass"))
    #expect(result["message"] == .string("ok"))
    #expect(result["via"] == .array([.string("record")]))
    #expect(result["record_version"] == .integer(1))
  }

  @Test
  func `a verdict with no note has no message member`() async throws {
    let document = try await workspace.run([
      "--json",
      "record",
      "shop.pay.card",
      "unit-tests",
      "pass",
    ])
    .document()

    guard case let .array(results)? = document["results"], let result = results.first else {
      Issue.record("no results")
      return
    }

    #expect(result["message"] == nil)
  }

  @Test
  func `the schema check fails a record document that breaks the schema`() async throws {
    let document = try await workspace.run([
      "--json",
      "record",
      "shop.pay.card",
      "unit-tests",
      "pass",
    ])
    .document()
    guard case var .object(members) = document else {
      Issue.record("not a document")
      return
    }

    members["kind"] = .string("verify")
    members["run_id"] = .string("short")

    #expect(try !failures(of: .object(members)).isEmpty)
  }

  @Test
  func `a refusal to record is a document of the error schema`() async throws {
    let result = await workspace.run(["--json", "record", "shop.pay.card", "nope", "pass"])
    let schema = try PublishedSchema(path: "schemas/output/cli-error.schema.json")

    #expect(try schema.failures(of: result.document()) == [])
  }
}

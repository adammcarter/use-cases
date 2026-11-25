import Foundation
import Testing
@testable import UseCasesCLI

struct StatusDocumentSchemaTests {
  private static let schemaPath = "schemas/output/cli-status.schema.json"

  private let workspace: StatusWorkspace

  init() async throws {
    workspace = try StatusWorkspace()
    try await workspace.recordEveryState()
  }

  private func failures(of document: JSONValue) throws -> [String] {
    try PublishedSchema(path: Self.schemaPath).failures(of: document)
  }

  private func useCases(_ document: JSONValue) -> [JSONValue] {
    guard case let .array(found)? = document["use_cases"] else {
      return []
    }

    return found
  }

  @Test(arguments: [
    ["--json", "status"],
    ["--json", "status", "shop.pay.card"],
    ["--json", "status", "shop.pay"],
    ["--json", "status", "--state", "draft"],
    ["--json", "status", "--state", "error"],
    ["--json", "status", "--gate"],
    ["--json", "status", "--gate", "--strict"],
  ])
  func `the document of every request follows the published schema`(
    arguments: [String],
  ) async throws {
    let document = try await workspace.run(arguments).document()

    #expect(try failures(of: document) == [])
  }

  @Test
  func `the document of a checkout where nothing has run lists as usual`() async throws {
    let fresh = try StatusWorkspace()

    let document = try await fresh.run(["--json", "status"]).document()

    #expect(try failures(of: document) == [])
    #expect(useCases(document).count == 7)
  }

  // @use-case:status.list#swift-tests.json
  @Test
  func `the document says every use case's state, status, approval and tier`() async throws {
    let document = try await workspace.run(["--json", "status"]).document()
    let card = try #require(useCases(document).first)
    let share = try #require(useCases(document).last)

    #expect(document["command"] == .string("status"))
    #expect(document["output_version"] == .integer(1))
    #expect(card["use_case"] == .string("shop.pay.card"))
    #expect(card["title"] == .string("Card"))
    #expect(card["state"] == .string("READY"))
    #expect(card["status"] == .string("failed"))
    #expect(card["approval"] == .string("unapproved"))
    #expect(card["value_tier"] == .string("core"))
    #expect(card["missing"] == nil)
    #expect(share["state"] == .string("DRAFT"))
    #expect(share["status"] == .string("draft"))
    #expect(share["missing"] == .array([.string("value_tier")]))
    #expect(share["routes"] == .array([]))
    #expect(share["value_tier"] == nil)
  }

  // @use-case:end status.list#swift-tests.json

  @Test
  func `a route says whether it gates, is linked, its status and a note with whole run ids`(
  ) async throws {
    let document = try await workspace.run(["--json", "status"]).document()
    let card = try #require(useCases(document).first)

    guard case let .array(routes)? = card["routes"] else {
      Issue.record("no routes")
      return
    }

    #expect(routes.map { $0["route"] } == [.string("check"), .string("extra")])
    #expect(routes.map { $0["gates"] } == [.boolean(true), .boolean(false)])
    #expect(routes.map { $0["linked"] } == [.boolean(true), .boolean(true)])
    #expect(routes.map { $0["status"] } == [.string("failed"), .string("verified")])

    guard case let .string(note)? = routes.first?["note"] else {
      Issue.record("no note")
      return
    }

    #expect(note.hasPrefix("run "))
    #expect(note.hasSuffix(" via record"))
    #expect(note.split(separator: " ")[1].count == 32)
  }

  @Test
  func `the summary counts the states of what is shown`() async throws {
    let document = try await workspace.run(["--json", "status", "--state", "failed,stale"])
      .document()

    #expect(document["summary"]?["total"] == .integer(2))
    #expect(document["summary"]?["by_status"]?["failed"] == .integer(1))
    #expect(document["summary"]?["by_status"]?["stale"] == .integer(1))
    #expect(document["summary"]?["by_status"]?["verified"] == nil)
  }

  @Test
  func `a plain status document has no gate`() async throws {
    let document = try await workspace.run(["--json", "status"]).document()

    #expect(document["gate"] == nil)
  }

  // MARK: - The check bites

  private func changed(
    _ edit: (inout [String: JSONValue]) -> Void,
    inUseCase index: Int,
  ) async throws -> JSONValue {
    let document = try await workspace.run(["--json", "status"]).document()
    guard case var .object(members) = document, case var .array(found)? = document["use_cases"],
          case var .object(useCase) = found[index]
    else {
      throw SchemaTestError.notADocument
    }

    edit(&useCase)
    found[index] = .object(useCase)
    members["use_cases"] = .array(found)

    return .object(members)
  }

  private enum SchemaTestError: Error {
    case notADocument
  }

  @Test
  func `a DRAFT with routes breaks the schema`() async throws {
    let document = try await changed(
      { useCase in
        useCase["routes"] = .array([.object([:])])
      },
      inUseCase: 6,
    )

    #expect(try !failures(of: document).isEmpty)
  }

  @Test
  func `a DRAFT without missing breaks the schema`() async throws {
    let document = try await changed(
      { useCase in
        useCase["missing"] = nil
      },
      inUseCase: 6,
    )

    #expect(try !failures(of: document).isEmpty)
  }

  @Test
  func `a READY use case with missing breaks the schema`() async throws {
    let document = try await changed(
      { useCase in
        useCase["missing"] = .array([.string("intent")])
      },
      inUseCase: 0,
    )

    #expect(try !failures(of: document).isEmpty)
  }

  @Test
  func `a READY use case listed as draft breaks the schema`() async throws {
    let document = try await changed(
      { useCase in
        useCase["status"] = .string("draft")
      },
      inUseCase: 0,
    )

    #expect(try !failures(of: document).isEmpty)
  }

  @Test
  func `a title that is not text breaks the schema`() async throws {
    let document = try await changed(
      { useCase in
        useCase["title"] = .integer(3)
      },
      inUseCase: 0,
    )

    #expect(try !failures(of: document).isEmpty)
  }

  @Test
  func `a state that is not a status breaks the summary`() async throws {
    let document = try await workspace.run(["--json", "status"]).document()
    guard case var .object(members) = document else {
      Issue.record("not a document")
      return
    }

    members["summary"] = .object([
      "total": .integer(1),
      "by_status": .object(["unknown": .integer(1)]),
    ])

    #expect(try !failures(of: .object(members)).isEmpty)
  }
}

import Foundation
import Testing
@testable import UseCasesTransformers

struct ResultsResponseTests {
  @Test
  func `an empty response still carries every required key`() throws {
    let json = try document(of: ResultsResponse())

    #expect(Set(json.keys) == ["contract", "results", "unlinked", "diagnostics"])
    #expect(json["contract"] as? Int == 1)
  }

  @Test
  func `a result has link and status, and tests and message only when there are some`() throws {
    let bare = try document(of: LinkResult(
      link: "k",
      status: .pass,
    ))
    let full = try document(
      of: LinkResult(
        link: "k",
        status: .fail,
        tests: ["a"],
        message: "why",
      ),
    )

    #expect(Set(bare.keys) == ["link", "status"])
    #expect(Set(full.keys) == ["link", "status", "tests", "message"])
    #expect(full["status"] as? String == "fail")
  }

  @Test
  func `an unlinked test always has file and line, null when unknown`() throws {
    let placed = try document(
      of: UnlinkedTest(
        test: "t",
        file: "a.py",
        line: 3,
        status: .pass,
      ),
    )
    let unplaced = try document(
      of: UnlinkedTest(
        test: "t",
        file: nil,
        line: nil,
        status: .incomplete,
      ),
    )

    #expect(Set(placed.keys) == ["test", "file", "line", "status"])
    #expect(Set(unplaced.keys) == ["test", "file", "line", "status"])
    #expect(unplaced["file"] is NSNull)
    #expect(unplaced["line"] is NSNull)
  }

  @Test
  func `a links response is contract 1 with links and diagnostics`() throws {
    let response = LinksResponse(
      links: [
        ProducedLink(
          useCase: "demo.a",
          route: nil,
          binding: "impl",
          role: .implementation,
          file: "src/a.py",
          range: LineRange(
            start: 1,
            end: 2,
          ),
        ),
        ProducedLink(
          useCase: "demo.a",
          route: "unit-tests",
          binding: "t",
          role: .validation,
          file: "tests/a.py",
          range: LineRange(
            start: 3,
            end: 3,
          ),
        ),
      ],
      diagnostics: ["note"],
    )

    let json = try document(of: response)
    let links = try #require(json["links"] as? [[String: Any]])

    #expect(Set(json.keys) == ["contract", "links", "diagnostics"])
    #expect(Set(links[0].keys) == ["use_case", "binding", "role", "file", "range"])
    #expect(Set(links[1].keys) == ["use_case", "route", "binding", "role", "file", "range"])
    #expect(links[1]["role"] as? String == "validation")
  }
}

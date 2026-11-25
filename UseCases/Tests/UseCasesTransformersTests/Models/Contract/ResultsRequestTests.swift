import Foundation
import Testing
@testable import UseCasesTransformers

struct ResultsRequestTests {
  private func decode(_ json: String) throws -> ResultsRequest {
    try JSONDecoder().decode(
      ResultsRequest.self,
      from: Data(json.utf8),
    )
  }

  private let full = """
  {
    "contract": 1,
    "job": "results",
    "use_cases": [{"id": "demo.a"}],
    "links": [{
      "key": "demo.a#unit-tests.t@tests/a.py:3",
      "source": "marker",
      "use_case": "demo.a",
      "route": "unit-tests",
      "binding": "t",
      "role": "validation",
      "file": "tests/a.py",
      "range": {"start": 3, "end": 4}
    }],
    "output": {"report_path": "/r", "exit_code": 1, "working_dir": "web"},
    "code_root": "/code",
    "settings": {"find": "file-line"}
  }
  """

  @Test
  func `the request of chapter 10 is read`() throws {
    let request = try decode(full)

    #expect(request.codeRoot == "/code")
    #expect(request.output == ReportOutput(
      reportPath: "/r",
      exitCode: 1,
      workingDirectory: "web",
    ))
    #expect(request.links.count == 1)
    #expect(request.links[0].key == "demo.a#unit-tests.t@tests/a.py:3")
    #expect(request.links[0].role == .validation)
    #expect(request.links[0].range == LineRange(
      start: 3,
      end: 4,
    ))
    #expect(try request.settings.string("find") == "file-line")
  }

  @Test
  func `fields a later core adds are ignored (ADR 015)`() throws {
    let future = full.replacingOccurrences(
      of: "\"contract\": 1,",
      with: "\"contract\": 1, \"from_the_future\": {\"any\": [1]},",
    ).replacingOccurrences(
      of: "\"binding\": \"t\",",
      with: "\"binding\": \"t\", \"from_the_future\": true,",
    ).replacingOccurrences(
      of: "\"report_path\": \"/r\",",
      with: "\"report_path\": \"/r\", \"from_the_future\": \"x\",",
    )

    #expect(try decode(future) == decode(full))
  }

  @Test
  func `an absent working folder is the project root and a null exit code is unknown`() throws {
    let request = try decode(
      """
      {"links": [], "code_root": "/c", "output": {"report_path": "/r", "exit_code": null}}
      """,
    )

    #expect(request.output.workingDirectory == ".")
    #expect(request.output.exitCode == nil)
    #expect(request.settings == .empty)
  }

  @Test
  func `a link with no range covers the whole file`() throws {
    let request = try decode(
      """
      {"links": [{"key": "k", "use_case": "a", "binding": "b", "role": "validation",
                  "file": "f"}],
       "code_root": "/c", "output": {"report_path": "/r"}}
      """,
    )

    #expect(request.links[0].range == nil)
  }

  @Test(arguments: [
    #"{"links": [], "code_root": "/c"}"#,
    #"{"links": [], "output": {"report_path": "/r"}}"#,
    #"{"code_root": "/c", "output": {"report_path": "/r"}}"#,
    #"{"links": [], "code_root": "/c", "output": {}}"#,
    #"{"links": [], "code_root": "/c", "output": {"report_path": "/r"}, "settings": 3}"#,
    #"[]"#,
  ])
  func `a request missing what the transformer needs is refused`(json: String) {
    #expect(throws: (any Error).self) {
      try decode(json)
    }
  }
}

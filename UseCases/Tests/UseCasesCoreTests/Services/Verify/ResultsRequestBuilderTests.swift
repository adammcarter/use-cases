import Testing
@testable import UseCasesCore

struct ResultsRequestBuilderTests {
  private let fixture: VerifyFixture

  init() throws {
    fixture = try VerifyFixture()
  }

  private func request(exitCode: Int32? = nil) throws -> [String: StoreJSONValue] {
    let resolved = try fixture.resolved()
    let validation = try #require(resolved.workspace.bridge?.validations.first)
    let built = ResultsRequestBuilder().request(
      for: validation,
      in: resolved.workspace,
      links: resolved.links,
      reportPath: "/work/.use-cases/runs/x/reports/unit-tests/unit.xml",
      exitCode: exitCode,
    )

    guard case let .object(members) = built else {
      Issue.record("not an object")
      return [:]
    }

    var fields: [String: StoreJSONValue] = [:]

    for member in members {
      fields[member.key] = member.value
    }

    return fields
  }

  @Test
  func `the request says contract 1 and the results job`() throws {
    let members = try request()

    #expect(members["contract"] == .integer(1))
    #expect(members["job"] == .string("results"))
    #expect(members["code_root"] == .string(fixture.workspace.path))
    #expect(members["settings"] == .object([]))
  }

  @Test
  func `the report is where the tests wrote it, and the exit code is null when unknown`()
    throws
  {
    let members = try request()

    #expect(
      members["output"] == .members([
        "report_path": .string("/work/.use-cases/runs/x/reports/unit-tests/unit.xml"),
        "exit_code": .null,
        "working_dir": .string("."),
      ]),
    )
  }

  @Test
  func `a command's exit code is told`() throws {
    let members = try request(exitCode: 1)

    guard case let .object(output)? = members["output"] else {
      Issue.record("no output")
      return
    }

    #expect(output.first { $0.key == "exit_code" }?.value == .integer(1))
  }

  @Test
  func `every link is told under its key, with lines and no bytes`() throws {
    let members = try request()

    guard case let .array(links)? = members["links"] else {
      Issue.record("no links")
      return
    }

    let key = try fixture.linkKey()
    let validation = links.first { link in
      guard case let .object(fields) = link else {
        return false
      }

      return fields.contains { field in
        field.key == "key" && field.value == .string(key)
      }
    }

    #expect(links.count == 2)
    #expect(validation != nil)
    #expect(
      validation == .members([
        "key": .string(key),
        "source": .string("marker"),
        "use_case": .string("app.toggle"),
        "route": .string("unit-tests"),
        "binding": .string("renders"),
        "role": .string("validation"),
        "file": .string("tests/t.swift"),
        "range": .members([
          "start": .integer(2),
          "end": .integer(2),
        ]),
      ]),
    )
  }

  @Test
  func `the use cases are told whole`() throws {
    let members = try request()

    guard case let .array(useCases)? = members["use_cases"] else {
      Issue.record("no use cases")
      return
    }

    #expect(useCases.count == 1)
  }
}

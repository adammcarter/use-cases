import Testing
@testable import UseCasesCore

/// The marker edits and registry events bind, unbind and rebind share, checked
/// against what the TypeScript's `bindingLifecycle.ts` returned.
struct BindingLifecycleTests {
  private typealias Fixtures = MarkerCommandsFixtures

  private func placement(_ value: JSONValue) throws -> MarkerPlacement {
    let modeName = try #require(value["mode"]?.stringValue)
    return try MarkerPlacement(
      mode: #require(MarkerMode(rawValue: modeName)),
      line: Fixtures.optionalInteger(value, "line"),
      startLine: Fixtures.optionalInteger(value, "startLine"),
      endLine: Fixtures.optionalInteger(value, "endLine"),
    )
  }

  @Test(arguments: MarkerCommandsGoldenCorpus.insertCaseNames)
  func `markers are inserted where the TypeScript inserts them`(caseName: String) throws {
    let entry = try Fixtures.entry(caseName, in: "insert_marker_lines")

    let result = try BindingLifecycle.insertMarkerLines(
      source: #require(entry["source"]?.stringValue),
      commentPrefix: #require(entry["prefix"]?.stringValue),
      slug: #require(entry["slug"]?.stringValue),
      placement: placement(#require(entry["placement"])),
    )

    #expect(Fixtures.wire(result.jsonValue) == Fixtures.wire(entry["result"]))
  }

  @Test
  func `a CRLF source keeps its carriage returns while the inserted marker has none`() throws {
    let entry = try Fixtures.entry("swift_func_crlf", in: "insert_marker_lines")
    let expected = try #require(entry["result"]?["contents"]?.stringValue)

    let result = try BindingLifecycle.insertMarkerLines(
      source: #require(entry["source"]?.stringValue),
      commentPrefix: "//",
      slug: #require(entry["slug"]?.stringValue),
      placement: MarkerPlacement(mode: .swiftFunction, line: 2),
    )

    #expect(result == .contents(expected))
    let lines = JavaScriptString.split(expected, on: CodeUnits.lineFeed)
    #expect(lines.map { $0.utf16.last == CodeUnits.carriageReturn } == [
      true,
      false,
      true,
      true,
      false,
    ])
  }

  @Test(arguments: MarkerCommandsGoldenCorpus.locateCaseNames)
  func `a slug's marker lines are located as the TypeScript locates them`(caseName: String) throws {
    let entry = try Fixtures.entry(caseName, in: "locate_marker_lines")

    let location = try BindingLifecycle.locateMarkerLines(
      filePath: "src/File.swift",
      contents: #require(entry["contents"]?.stringValue),
      commentPrefix: #require(entry["prefix"]?.stringValue),
      slug: #require(entry["slug"]?.stringValue),
    )

    #expect(Fixtures.wire(location?.jsonValue ?? .null) == Fixtures.wire(entry["result"]))
  }

  @Test(arguments: MarkerCommandsGoldenCorpus.removeCaseNames)
  func `marker lines are removed as the TypeScript removes them`(caseName: String) throws {
    let entry = try Fixtures.entry(caseName, in: "remove_marker_lines")
    let location = try #require(entry["location"])

    let contents = try BindingLifecycle.removeMarkerLines(
      contents: #require(entry["contents"]?.stringValue),
      location: MarkerLocation(
        filePath: #require(location["file_path"]?.stringValue),
        startLine: #require(Fixtures.optionalInteger(location, "start_line")),
        endLine: Fixtures.optionalInteger(location, "end_line"),
      ),
    )

    #expect(try contents == #require(entry["result"]?.stringValue))
  }

  @Test
  func `registry events are written byte for byte as the TypeScript writes them`() throws {
    for entry in try Fixtures.section("registry_events") {
      let input = try #require(entry["input"])
      let eventInput = try RegistryEventInput(
        command: #require(input["command"]?.stringValue),
        rowIdentifier: #require(input["rowId"]?.stringValue),
        bindingSlug: #require(input["bindingSlug"]?.stringValue),
        reason: #require(input["reason"]?.stringValue),
        eventIdentifier: #require(input["eventId"]?.stringValue),
        createdAt: #require(input["createdAt"]?.stringValue),
        version: input["version"]?.stringValue,
      )
      let event = entry["kind"]?.stringValue == "registered"
        ? BindingLifecycle.bindingRegisteredEvent(eventInput)
        : BindingLifecycle.bindingReleasedEvent(eventInput)

      #expect(try Fixtures.wire(event) == #require(entry["json"]?.stringValue))
    }
  }
}

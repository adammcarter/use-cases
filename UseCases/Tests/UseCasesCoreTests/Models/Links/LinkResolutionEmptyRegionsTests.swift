import Testing
@testable import UseCasesCore

struct LinkResolutionEmptyRegionsTests {
  private func resolution(writing files: [String: String]) throws -> LinkResolution {
    let fixture = try WorkspaceFixture(rootConfiguration: YAMLSamples.root)
    try fixture.writeUseCase()

    for (path, text) in files {
      try fixture.write(
        path,
        text,
      )
    }

    return try fixture.resolved()
  }

  @Test(arguments: ["", "\n\n   \n"])
  func `an empty region is tied to the use case it marks`(inside: String) throws {
    let resolution = try resolution(writing: [
      "src/a.swift": "// \(MarkerText.sentinel)app.toggle#code\n\(inside)"
        + "// \(MarkerText.sentinel)end app.toggle#code\n",
    ])

    let regions = resolution.emptyMarkerRegions

    #expect(regions.map(\.useCase) == ["app.toggle"])
    #expect(
      regions.map(\.text)
        ==
        [
          "src/a.swift:2: its marked region is empty; if the code moved, move its markers with it",
        ],
    )
  }

  @Test
  func `a region with code is no empty region`() throws {
    let resolution = try resolution(writing: [
      "src/a.swift": LinkSamples.marked("app.toggle#code", "work()"),
    ])

    #expect(resolution.emptyMarkerRegions.isEmpty)
  }

  @Test
  func `a validation region is tied to its use case too`() throws {
    let resolution = try resolution(writing: [
      "src/a.swift": LinkSamples.marked("app.toggle#manual.check", ""),
    ])

    #expect(resolution.emptyMarkerRegions.map(\.useCase) == ["app.toggle"])
  }

  @Test
  func `two empty regions in one file are both found`() throws {
    let resolution = try resolution(writing: [
      "src/a.swift": LinkSamples.marked("app.toggle#one", "")
        + LinkSamples.marked("app.toggle#two", ""),
    ])

    #expect(resolution.emptyMarkerRegions.count == 2)
  }

  @Test
  func `other warnings are not empty regions`() throws {
    let resolution = try resolution(writing: [
      "src/a.swift": LinkSamples.marked("app.nothing#code", "work()"),
    ])

    #expect(!resolution.warningLines.isEmpty)
    #expect(resolution.emptyMarkerRegions.isEmpty)
  }
}

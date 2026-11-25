import Foundation
import Testing
@testable import UseCasesCore

struct LinkResolverManualRangeTests {
  private let fixture: WorkspaceFixture

  init() throws {
    fixture = try WorkspaceFixture()
  }

  private func resolve(
    bindings: [String] = [],
    routeBindings: [String] = [],
  ) throws -> LinkResolution {
    try fixture.writeUseCase(
      bindings: bindings,
      routeBindings: routeBindings,
    )

    return try fixture.resolved()
  }

  @Test
  func `a range with columns links the lines it names`() throws {
    try fixture.write("src/app.swift", "first\n12ßé6\nlast\n")

    let resolution = try resolve(
      bindings: [
        LinkSamples.binding(
          "part",
          file: "src/app.swift",
          start: (2, 3),
          end: (2, 5),
        ),
      ],
    )
    let link = try #require(resolution.links.first)

    #expect(link.startLine == 2)
    #expect(link.endLine == 2)
    #expect(link.span == 8 ..< 13)
  }

  @Test
  func `a range cannot be cut from binary content`() throws {
    try fixture.write("assets/logo.bin", bytes: [0xFF, 0xFE, 0x00, 0x80, 0x0A, 0x00])

    let resolution = try resolve(
      bindings: [
        LinkSamples.binding(
          "logo",
          file: "assets/logo.bin",
          start: (1, nil),
          end: (1, nil),
        ),
      ],
    )

    #expect(resolution.isInvalid)
    #expect(resolution.problems(containing: "not text").count == 1)
  }

  @Test
  func `a start column more than one past the end of its line is INVALID`() throws {
    try fixture.write("src/a.txt", "abcd\nxy\n")

    let resolution = try resolve(
      bindings: [
        LinkSamples.binding(
          "a",
          file: "src/a.txt",
          start: (1, 6),
          end: (2, nil),
        ),
      ],
    )

    #expect(resolution.isInvalid)
    #expect(resolution.problems(containing: "start column 6 on line 1").count == 1)
  }

  @Test
  func `an end column past the end of its line is INVALID`() throws {
    try fixture.write("src/a.txt", "abcd\nxy\n")

    let resolution = try resolve(
      bindings: [
        LinkSamples.binding(
          "a",
          file: "src/a.txt",
          start: (1, 2),
          end: (2, 3),
        ),
      ],
    )

    #expect(resolution.isInvalid)
    #expect(resolution.problems(containing: "end column 3 on line 2").count == 1)
  }

  @Test(arguments: [(3, 3), (1, 3), (2, 9)])
  func `a line past the end of the file is INVALID`(case example: (start: Int, end: Int)) throws {
    try fixture.write("src/a.txt", "one\ntwo\n")

    let resolution = try resolve(
      bindings: [
        LinkSamples.binding(
          "a",
          file: "src/a.txt",
          start: (example.start, nil),
          end: (example.end, nil),
        ),
      ],
    )

    #expect(resolution.isInvalid)
    #expect(resolution.problems(containing: "'src/a.txt' has 2 lines").count == 1)
  }

  @Test
  func `a range in an empty file is outside it`() throws {
    try fixture.write("src/empty.txt", "")

    let resolution = try resolve(
      bindings: [
        LinkSamples.binding(
          "a",
          file: "src/empty.txt",
          start: (1, nil),
          end: (1, nil),
        ),
      ],
    )

    #expect(resolution.isInvalid)
    #expect(resolution.problems(containing: "is empty").count == 1)
  }

  @Test
  func `an end column on an empty line is INVALID`() throws {
    try fixture.write("src/a.txt", "a\n\nb\n")

    let resolution = try resolve(
      bindings: [
        LinkSamples.binding(
          "a",
          file: "src/a.txt",
          start: (1, nil),
          end: (2, 1),
        ),
      ],
    )

    #expect(resolution.isInvalid)
    #expect(resolution.problems(containing: "column").count == 1)
  }

  @Test(arguments: [(3, true), (4, false)])
  func `a leading byte-order mark is not a column`(case example: (end: Int, valid: Bool)) throws {
    try fixture.write("src/a.txt", bytes: [0xEF, 0xBB, 0xBF] + Array("abc\nxyz\n".utf8))

    let resolution = try resolve(
      bindings: [
        LinkSamples.binding(
          "a",
          file: "src/a.txt",
          start: (1, 1),
          end: (1, example.end),
        ),
      ],
    )

    #expect(!resolution.isInvalid == example.valid)
  }

  @Test
  func `an empty range is valid and warns at the file it links`() throws {
    try fixture.write("src/a.txt", "abcd\n")

    let resolution = try resolve(
      bindings: [
        LinkSamples.binding(
          "a",
          file: "src/a.txt",
          start: (1, 3),
          end: (1, 2),
        ),
      ],
    )

    #expect(resolution.links.count == 1)
    #expect(resolution.links.first?.span == 2 ..< 2)
    #expect(resolution.problems.isEmpty)
    #expect(resolution.warnings(containing: "empty range").count == 1)
    #expect(resolution.warningLines.first?.hasPrefix("src/a.txt:1: ") == true)
  }

  @Test
  func `an empty file bound whole is valid and warns at the file`() throws {
    try fixture.write("src/empty.py", "")
    try fixture.write("src/full.py", "x = 1\n")

    let resolution = try resolve(
      bindings: [
        LinkSamples.binding("a", file: "src/empty.py"),
        LinkSamples.binding("b", file: "src/full.py"),
      ],
    )
    let warnings = resolution.warnings(containing: "empty whole-file binding")

    #expect(resolution.links.map(\.binding) == ["a", "b"])
    #expect(resolution.links.first?.startLine == 1)
    #expect(resolution.links.first?.endLine == 1)
    #expect(warnings.count == 1)
    #expect(warnings.first?.hasPrefix("src/empty.py:1: ") == true)
  }
}

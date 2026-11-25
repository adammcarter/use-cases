import Testing
@testable import UseCasesCore

struct LinkResolverMarkersTests {
  private let fixture: WorkspaceFixture

  init() throws {
    fixture = try WorkspaceFixture()
    try fixture.writeUseCase()
  }

  @Test
  func `a marker pair makes an implementation link that needs no YAML entry`() throws {
    try fixture.write("src/app.swift", LinkSamples.marked("app.toggle#render", "draw()"))

    let resolution = try fixture.resolved()
    let link = try #require(resolution.links.first)

    #expect(resolution.links.count == 1)
    #expect(link.key == "app.toggle#render@src/app.swift:2")
    #expect(link.source == .marker)
    #expect(link.role == .implementation)
    #expect(link.useCase == "app.toggle")
    #expect(link.route == nil)
    #expect(link.binding == "render")
    #expect(link.file == "src/app.swift")
    #expect(link.startLine == 2)
    #expect(link.endLine == 2)
    #expect(resolution.problems.isEmpty)
    #expect(resolution.warningLines.isEmpty)
  }

  @Test
  func `a region whose end sentinel is the last line without a line break still links`() throws {
    try fixture.write(
      "src/app.js",
      "// \(MarkerText.sentinel)app.toggle#render\nexport const add = 1;\n"
        + "// \(MarkerText.sentinel)end app.toggle#render",
    )

    let link = try #require(fixture.resolved().links.first)

    #expect(link.startLine == 2)
    #expect(link.endLine == 2)
  }

  @Test
  func `a marker that names a route makes a validation link for it`() throws {
    try fixture.write(
      "tests/app_tests.swift",
      LinkSamples.marked("app.toggle#manual.renders", "check()\ncheck()"),
    )

    let link = try #require(fixture.resolved().links.first)

    #expect(link.role == .validation)
    #expect(link.route == LinkSamples.route)
    #expect(link.binding == "renders")
    #expect(link.key == "app.toggle#manual.renders@tests/app_tests.swift:2")
    #expect(link.startLine == 2)
    #expect(link.endLine == 3)
  }

  @Test
  func `one marker identity may have many regions`() throws {
    let region = LinkSamples.marked("app.toggle#render", "draw()")
    try fixture.write("src/a.swift", region + region)
    try fixture.write("src/b.swift", region)

    let resolution = try fixture.resolved()

    #expect(
      resolution.keys == [
        "app.toggle#render@src/a.swift:2",
        "app.toggle#render@src/a.swift:5",
        "app.toggle#render@src/b.swift:2",
      ],
    )
    #expect(resolution.problems.isEmpty)
  }

  @Test
  func `a well-paired marker for an unknown use case warns and links nothing`() throws {
    try fixture.write("src/app.swift", LinkSamples.marked("app.nope#render", "draw()"))

    let resolution = try fixture.resolved()

    #expect(resolution.links.isEmpty)
    #expect(resolution.problems.isEmpty)
    #expect(resolution.warnings(containing: "unknown use case").count == 1)
    #expect(resolution.warningLines.first?.hasPrefix("src/app.swift:2: ") == true)
  }

  @Test
  func `a well-paired marker for an unknown route warns and links nothing`() throws {
    try fixture.write("src/app.swift", LinkSamples.marked("app.toggle#nope.render", "draw()"))

    let resolution = try fixture.resolved()

    #expect(resolution.links.isEmpty)
    #expect(resolution.problems.isEmpty)
    #expect(resolution.warnings(containing: "unknown route").count == 1)
  }

  @Test
  func `a malformed marker id warns and is ignored`() throws {
    try fixture.write("src/app.swift", "// \(MarkerText.sentinel)Bad_ID\ncode\n")

    let resolution = try fixture.resolved()

    #expect(resolution.links.isEmpty)
    #expect(resolution.problems.isEmpty)
    #expect(resolution.warnings(containing: "malformed marker id").count == 1)
  }

  @Test(
    arguments: [
      ("// \(MarkerText.sentinel)app.nope#x\nz\n", "never closed"),
      ("z\n// \(MarkerText.sentinel)end app.nope#x\n", "has no start"),
      ("// \(MarkerText.sentinel)app.toggle#nope.x\nz\n", "never closed"),
      (
        "// \(MarkerText.sentinel)app.nope#a\n// \(MarkerText.sentinel)app.nope#b\n"
          + "// \(MarkerText.sentinel)end app.nope#a\n// \(MarkerText.sentinel)end app.nope#b\n",
        "cross",
      ),
      (
        "// \(MarkerText.sentinel)app.nope#a\n// \(MarkerText.sentinel)app.nope#a\n"
          + "// \(MarkerText.sentinel)end app.nope#a\n// \(MarkerText.sentinel)end app.nope#a\n",
        "nested inside itself",
      ),
    ],
  )
  func `pairing comes before the lookup, so a broken marker for an unknown target is INVALID`(
    case example: (code: String, reason: String),
  ) throws {
    try fixture.write("src/x.js", example.code)

    let resolution = try fixture.resolved()

    #expect(resolution.isInvalid)
    #expect(resolution.links.isEmpty)
    #expect(resolution.problems(containing: example.reason).count == 1)
  }

  @Test
  func `a region with no content links and warns`() throws {
    try fixture.write(
      "src/app.swift",
      "// \(MarkerText.sentinel)app.toggle#render\n"
        + "// \(MarkerText.sentinel)end app.toggle#render\n",
    )

    let resolution = try fixture.resolved()

    #expect(resolution.links.count == 1)
    #expect(resolution.warnings(containing: "empty marker region").count == 1)
  }

  @Test
  func `a file that is not strict UTF-8 and holds the sentinel warns and links nothing`() throws {
    var bytes = Array("// \(MarkerText.sentinel)app.toggle#render\n".utf8)
    bytes += [0xFF, 0x0A]
    bytes += Array("// \(MarkerText.sentinel)end app.toggle#render\n".utf8)
    try fixture.write("src/app.bin", bytes: bytes)

    let resolution = try fixture.resolved()

    #expect(resolution.links.isEmpty)
    #expect(resolution.problems.isEmpty)
    #expect(resolution.warnings(containing: "unsupported-text").count == 1)
  }

  @Test
  func `a file that is not UTF-8 and holds no sentinel is never warned about`() throws {
    try fixture.write("src/app.bin", bytes: [0xFF, 0xFE, 0x00, 0x80, 0x0A])
    try fixture.write("src/other.bin", bytes: [0xC3, 0x28, 0x0A])

    let resolution = try fixture.resolved()

    #expect(resolution.warnings(containing: "src/other.bin").isEmpty)
  }

  @Test(arguments: WideForm.allCases)
  func `a file starting with a UTF-16 or UTF-32 byte-order mark warns once and links nothing`(
    form: WideForm,
  ) throws {
    let marker = LinkSamples.marked("app.toggle#render", "draw()")
    try fixture.write("src/wide.txt", bytes: form.bytes(of: marker))

    let resolution = try fixture.resolved()

    #expect(resolution.links.isEmpty)
    #expect(resolution.problems.isEmpty)
    #expect(resolution.warnings(containing: "src/wide.txt").count == 1)
  }
}

import Foundation
import Testing
@testable import UseCasesCore

struct LinkResolverManualTests {
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
  func `a whole-file binding links the file from line 1 to its last line`() throws {
    try fixture.write("config/auth.yml", "a: 1\nb: 2\nc: 3\n")

    let resolution = try resolve(bindings: [LinkSamples.binding(
      "auth-config",
      file: "config/auth.yml",
    )])
    let link = try #require(resolution.links.first)

    #expect(resolution.links.count == 1)
    #expect(link.key == "app.toggle#auth-config@config/auth.yml:1")
    #expect(link.source == .manual)
    #expect(link.role == .implementation)
    #expect(link.route == nil)
    #expect(link.startLine == 1)
    #expect(link.endLine == 3)
    #expect(resolution.problems.isEmpty)
    #expect(resolution.warningLines.isEmpty)
  }

  @Test
  func `a binding under a route is a validation link for it`() throws {
    try fixture.write("tests/t.swift", "one\ntwo\nthree\n")

    let resolution = try resolve(
      routeBindings: [
        LinkSamples.binding(
          "helper-test",
          file: "tests/t.swift",
          start: (2, nil),
          end: (3, nil),
        ),
      ],
    )
    let link = try #require(resolution.links.first)

    #expect(link.role == .validation)
    #expect(link.route == LinkSamples.route)
    #expect(link.key == "app.toggle#manual.helper-test@tests/t.swift:2")
    #expect(link.endLine == 3)
  }

  @Test(
    arguments: [
      ("", 1),
      ("a", 1),
      ("a\n", 1),
      ("a\nb", 2),
      ("a\nb\n", 2),
      ("a\n\n", 2),
      ("\n", 1),
      ("a\r\nb\r\n", 2),
    ],
  )
  func `a whole-file link ends at the last line holding bytes`(
    case example: (content: String, last: Int),
  ) throws {
    try fixture.write("src/a.txt", example.content)

    let link = try #require(
      resolve(bindings: [LinkSamples.binding("a", file: "src/a.txt")]).links.first,
    )

    #expect(link.startLine == 1)
    #expect(link.endLine == example.last)
  }

  @Test
  func `a whole-file binding may bind binary content`() throws {
    try fixture.write("assets/logo.bin", bytes: [0xFF, 0xFE, 0x00, 0x80, 0x0A, 0x00])

    let resolution = try resolve(bindings: [LinkSamples.binding("logo", file: "assets/logo.bin")])

    #expect(resolution.links.first?.span == 0 ..< 6)
    #expect(resolution.problems.isEmpty)
  }

  @Test
  func `a binding to a missing file is INVALID and filed under the definition file`() throws {
    let resolution = try resolve(bindings: [LinkSamples.binding("x", file: "src/Nope.swift")])

    #expect(resolution.isInvalid)
    #expect(resolution.links.isEmpty)
    #expect(resolution.problems.count == 1)
    #expect(resolution.problems.first?.hasPrefix("use-cases/toggle.yml: ") == true)
    #expect(resolution.problems.first?.contains("is missing") == true)
    #expect(resolution.problems.first?.contains("src/Nope.swift") == true)
  }

  @Test
  func `a path spelled in another case is INVALID and the message gives the disk's spelling`()
    throws
  {
    try fixture.write("src/math.js", "x\n")

    let resolution = try resolve(bindings: [LinkSamples.binding("x", file: "Src/math.js")])

    #expect(resolution.isInvalid)
    #expect(resolution.problems.count == 1)
    #expect(resolution.problems.first?.contains("spelled 'src") == true)
    #expect(resolution.problems.first?.contains("paths must match exactly") == true)
  }

  @Test
  func `a path spelled in another Unicode form is INVALID`() throws {
    let composed = "src/caf\u{E9}.js"
    let decomposed = "src/cafe\u{301}.js"
    try fixture.write(composed, "x\n")
    let listed = try LocalFileSystem().entries(in: fixture.directory.location(of: "src"))
      .map(\.name)

    guard !listed.contains(where: { $0.isExactlyEqual(to: "cafe\u{301}.js") }) else {
      return
    }

    let resolution = try resolve(bindings: [LinkSamples.binding("x", file: decomposed)])

    #expect(resolution.isInvalid)
    #expect(resolution.problems.first?.contains("paths must match exactly") == true)
  }

  @Test
  func `a binding to a folder is INVALID`() throws {
    try fixture.write("src/inner.swift", "x\n")

    let resolution = try resolve(bindings: [LinkSamples.binding("x", file: "src")])

    #expect(resolution.isInvalid)
    #expect(resolution.problems.first?.contains("a folder") == true)
  }

  @Test
  func `a binding to a pipe is INVALID and the pipe is never opened`() throws {
    try fixture.directory.makeFIFO("src/pipe.fifo")

    let resolution = try resolve(bindings: [LinkSamples.binding("x", file: "src/pipe.fifo")])

    #expect(resolution.isInvalid)
    #expect(resolution.problems(containing: "pipe, socket or device").count >= 1)
  }

  @Test
  func `a binding through a symlinked folder is INVALID and says the symlink is never followed`()
    throws
  {
    try fixture.write("real/code.swift", "x\n")
    try fixture.directory.symlink("alias", to: "real")

    let resolution = try resolve(bindings: [LinkSamples.binding("x", file: "alias/code.swift")])

    #expect(resolution.isInvalid)
    #expect(resolution.problems.count == 1)
    #expect(
      resolution.problems.first?.contains(
        "'alias/code.swift' passes through 'alias', a symlink, which is never followed",
      ) == true,
    )
    #expect(resolution.problems.first?.contains("is missing") == false)
  }

  @Test
  func `a binding to a symlink tracks the text it points with, wherever it points`() throws {
    let outside = try TemporaryDirectory()
    try outside.write("secret.js", "outside the project\nmore\n")
    try fixture.directory.symlink("src/escape.js", to: "../../secret.js")
    try fixture.directory.symlink("src/absolute.js", to: outside.location(of: "secret.js").path)

    let resolution = try resolve(
      bindings: [
        LinkSamples.binding("relative", file: "src/escape.js"),
        LinkSamples.binding("absolute", file: "src/absolute.js"),
      ],
    )
    let relative = try #require(resolution.links.first { $0.binding == "relative" })
    let absolute = try #require(resolution.links.first { $0.binding == "absolute" })

    #expect(relative.span == 0 ..< "../../secret.js".utf8.count)
    #expect(relative.endLine == 1)
    #expect(absolute.span.count == outside.location(of: "secret.js").path.utf8.count)
    #expect(resolution.problems.isEmpty)
  }

  @Test(arguments: [
    ("vendor/lib.js", "vendor"),
    (".git/config", nil),
    ("build/out.js", "build/**"),
  ])
  func `a binding into excluded content is valid and warns at the file it links`(
    case example: (path: String, exclude: String?),
  ) throws {
    let configuration =
      example.exclude.map { pattern in
        YAMLSamples.root + "discovery:\n  exclude:\n    - \"\(pattern)\"\n"
      } ?? YAMLSamples.root
    let fixture = try WorkspaceFixture(rootConfiguration: configuration)
    try fixture.write(example.path, "x = 1\n")
    try fixture.writeUseCase(bindings: [LinkSamples.binding("lib", file: example.path)])

    let resolution = try fixture.resolved()
    let warnings = resolution.warnings(containing: "points at excluded content")

    #expect(resolution.links.map(\.file) == [example.path])
    #expect(resolution.problems.isEmpty)
    #expect(warnings.count == 1)
    #expect(warnings.first?.hasPrefix("\(example.path):1: ") == true)
  }

  @Test
  func `a binding in a child scope may link code anywhere in the workspace`() throws {
    try fixture.write("child/use-cases.yml", YAMLSamples.child(prefix: "child"))
    try fixture.write(
      "child/use-cases/c.yml",
      YAMLSamples.file(YAMLSamples.useCase("deep", extra: """
          bindings:
            - id: shared
              kind: manual
              locator: { file: lib/shared.swift }

      """)),
    )
    try fixture.write("lib/shared.swift", "x\n")
    try fixture.writeUseCase()

    let resolution = try fixture.resolved()

    #expect(resolution.keys == ["app.child.deep#shared@lib/shared.swift:1"])
  }
}

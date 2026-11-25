import Foundation
import Testing
import UseCasesCore
@testable import UseCasesCLI

struct LinksCommandTests {
  private let workspace: LinksWorkspace

  init() throws {
    workspace = try LinksWorkspace()
  }

  private func writeCode() throws {
    try workspace.folder.write(
      "src/pay.swift",
      LinksWorkspace.marked("shop.pay#top")
        + LinksWorkspace.marked("shop.pay.card#charge")
        + LinksWorkspace.marked("shop.pay.card#unit-tests.charges", "check()"),
    )
    try workspace.folder.write(
      "src/cart.swift",
      LinksWorkspace.marked("shop.cart.add#put") + "// @use-case:BAD\n",
    )
  }

  private func useCases(of result: CommandResult) throws -> Set<String> {
    guard case let .array(links)? = try result.document()["links"] else {
      return []
    }

    return Set(
      links.compactMap { link in
        guard case let .string(useCase)? = link["use_case"] else {
          return nil
        }

        return useCase
      },
    )
  }

  private func diagnostics(of result: CommandResult) throws -> JSONValue? {
    try result.document()["diagnostics"]
  }

  @Test
  func `links lists every link as one JSON document in the shape transformers receive`(
  ) async throws {
    try writeCode()

    let result = await workspace.run(["--json", "links"])
    let document = try result.document()

    #expect(result.exitCode == 0)
    #expect(result.standardError.isEmpty)
    #expect(document["command"] == .string("links"))
    #expect(document["output_version"] == .integer(1))
    #expect(
      try useCases(of: result) == [
        "shop.pay", "shop.pay.card", "shop.cart.add",
      ],
    )
  }

  @Test
  func `a link has its key, source, role, file and lines, and a route only when it validates`(
  ) async
    throws
  {
    try writeCode()

    let document = try await workspace.run(["--json", "links", "shop.pay.card"]).document()

    #expect(
      document["links"] == .array([
        .object([
          "key": .string("shop.pay.card#charge@src/pay.swift:5"),
          "source": .string("marker"),
          "use_case": .string("shop.pay.card"),
          "binding": .string("charge"),
          "role": .string("implementation"),
          "file": .string("src/pay.swift"),
          "range": .object(["start": .integer(5), "end": .integer(5)]),
        ]),
        .object([
          "key": .string("shop.pay.card#unit-tests.charges@src/pay.swift:8"),
          "source": .string("marker"),
          "use_case": .string("shop.pay.card"),
          "route": .string("unit-tests"),
          "binding": .string("charges"),
          "role": .string("validation"),
          "file": .string("src/pay.swift"),
          "range": .object(["start": .integer(8), "end": .integer(8)]),
        ]),
      ]),
    )
  }

  @Test
  func `a manual binding is a link of source manual covering the whole file`() async throws {
    let document = try await workspace.run(["--json", "links", "shop.cart.add"]).document()

    #expect(
      document["links"] == .array([
        .object([
          "key": .string("shop.cart.add#config@config/cart.yml:1"),
          "source": .string("manual"),
          "use_case": .string("shop.cart.add"),
          "binding": .string("config"),
          "role": .string("implementation"),
          "file": .string("config/cart.yml"),
          "range": .object(["start": .integer(1), "end": .integer(1)]),
        ]),
      ]),
    )
  }

  @Test
  func `an exact use case id wins over a prefix, and a prefix narrows to the use cases under it`(
  ) async
    throws
  {
    try writeCode()

    #expect(try await useCases(of: workspace.run(["--json", "links", "shop.pay"])) ==
      ["shop.pay"])
    #expect(
      try await useCases(of: workspace.run(["--json", "links", "shop.cart"])) ==
        ["shop.cart.add"],
    )
    #expect(
      try await useCases(of: workspace.run(["--json", "links", "shop"]))
        == ["shop.pay", "shop.pay.card", "shop.cart.add"],
    )
  }

  @Test
  func `a use case with no links is a known target with no links`() async throws {
    try writeCode()

    let result = await workspace.run(["--json", "links", "shop.cart.share"])

    #expect(result.exitCode == 0)
    #expect(try result.document()["links"] == .array([]))
  }

  @Test
  func `the target narrows the links and never the diagnostics`() async throws {
    try writeCode()

    let everything = try await diagnostics(of: workspace.run(["--json", "links"]))
    let narrowed = try await diagnostics(of: workspace.run(["--json", "links", "shop.pay"]))
    let unrelated = try await diagnostics(of: workspace.run([
      "--json",
      "links",
      "shop.cart.share",
    ]))

    guard case let .array(lines)? = everything else {
      Issue.record("the diagnostics are not a list")
      return
    }

    #expect(lines.count == 1)
    #expect(narrowed == everything)
    #expect(unrelated == everything)
  }

  @Test(arguments: ["shop.nope", "shop.pa", "shop.pay.", "", "SHOP"])
  func `a target that names no use case or id prefix is a usage refusal`(
    target: String,
  ) async throws {
    let result = await workspace.run(["--json", "links", target])
    let error = try #require(try result.document()["error"])

    #expect(result.exitCode == 2)
    #expect(error["kind"] == .string("usage"))
    #expect(try result.document()["command"] == .string("links"))
    #expect(result.standardError.hasPrefix("error: no use case or id prefix"))
    #expect(result.standardError.contains("'\(target)'"))
  }

  @Test
  func `without json a person reads one line per link and then the warnings`() async throws {
    try writeCode()

    let result = await workspace.run(["links"])
    let lines = result.standardOutput.split(separator: "\n").map(String.init)

    #expect(result.exitCode == 0)
    #expect(result.standardError.isEmpty)
    #expect(
      lines.dropLast() == [
        "shop.cart.add  implementation         config/cart.yml:1",
        "shop.cart.add  implementation         src/cart.swift:2",
        "shop.pay       implementation         src/pay.swift:2",
        "shop.pay.card  implementation         src/pay.swift:5",
        "shop.pay.card  validation unit-tests  src/pay.swift:8",
      ],
    )
    #expect(lines.last?.hasPrefix("warning: src/cart.swift:4: malformed marker id") == true)
  }

  @Test
  func `a person is told when there are no links`() async {
    let result = await workspace.run(["links", "shop.pay"])

    #expect(result.exitCode == 0)
    #expect(result.standardOutput == "no links\n")
  }

  @Test
  func `a person sees the warnings of the whole workspace after the links`() async throws {
    try writeCode()

    let result = await workspace.run(["links", "shop.pay"])
    let lines = result.standardOutput.split(separator: "\n").map(String.init)

    #expect(lines.last?.hasPrefix("warning: src/cart.swift:4: malformed marker id") == true)
  }

  @Test
  func `a problem in the links refuses the request as invalid, a problem per line`() async throws {
    try workspace.folder.write("src/a.swift", "// @use-case:shop.pay.card#charge\nwork()\n")
    try workspace.folder.write("src/b.swift", "// @use-case:end shop.pay.card#charge\n")

    for arguments in [["links"], ["--json", "links"], ["--json", "links", "shop.nope"]] {
      let result = await workspace.run(arguments)
      let lines = result.standardError.split(separator: "\n").map(String.init)

      #expect(result.exitCode == 2)
      #expect(lines.count == 2)
      #expect(lines.first?.hasPrefix("error: src/a.swift:1: ") == true)
      #expect(lines.last?.hasPrefix("src/b.swift:1: ") == true)
    }
  }

  @Test
  func `with json a link problem is a document of kind invalid carrying the same message`(
  ) async throws {
    try workspace.folder.write("src/a.swift", "// @use-case:shop.pay.card#charge\nwork()\n")

    let result = await workspace.run(["--json", "links"])
    let error = try #require(try result.document()["error"])

    #expect(result.exitCode == 2)
    #expect(error["kind"] == .string("invalid"))
    #expect(try result.document()["command"] == .string("links"))
    #expect(try result.document()["links"] == nil)
    guard case let .string(message)? = error["message"] else {
      Issue.record("the error has no message")
      return
    }
    #expect(result.standardError.contains(message))
  }

  @Test
  func `an invalid workspace is refused exactly as validate refuses it`() async throws {
    try workspace.folder.write("use-cases/broken.yml", "use_cases: 5\n")

    let links = await workspace.run(["--json", "links"])
    let validate = await workspace.run(["--json", "validate"])

    #expect(links.exitCode == 2)
    #expect(links.standardError == validate.standardError)
    #expect(try links.document()["error"] == validate.document()["error"])
  }

  @Test
  func `the options work after the command too, and the output is the same every time`(
  ) async throws {
    try writeCode()
    let path = workspace.folder.url.path

    let before = await CommandLineRunner(
      loader: WorkspaceLoader(),
      workingDirectory: URL(fileURLWithPath: "/"),
    ).run(arguments: ["--workspace", path, "--json", "links"])
    let after = await CommandLineRunner(
      loader: WorkspaceLoader(),
      workingDirectory: URL(fileURLWithPath: "/"),
    ).run(arguments: ["links", "--json", "--workspace", path])

    #expect(before.exitCode == 0)
    #expect(before == after)
    #expect(await before == workspace.run(["--json", "links"]))
  }
}

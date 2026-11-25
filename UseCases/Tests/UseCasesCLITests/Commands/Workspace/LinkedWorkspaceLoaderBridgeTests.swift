import Foundation
import Testing
import UseCasesCore
import UseCasesTestSupport
@testable import UseCasesCLI

struct LinkedWorkspaceLoaderBridgeTests {
  private static let linkBridge = "schema_version: 1\nlinks:\n  - transformer: tools/links\n"

  /// A links answer: one validation link around the first two lines of `src/pay.swift`.
  private static let answer = """
  {"contract":1,"links":[{"use_case":"shop.pay.card","route":"unit-tests",\
  "binding":"charges","role":"validation","file":"src/pay.swift","range":{"start":1,"end":2}}],\
  "diagnostics":["read 1 test"]}
  """

  private let workspace: LinksWorkspace

  init() throws {
    workspace = try LinksWorkspace()
    try workspace.folder.write("src/pay.swift", "one\ntwo\nthree\n")
  }

  private func load(
    transformers: (any TransformerLinkProviding)? = nil,
  ) async throws(LinkedWorkspaceError) -> LinkedWorkspace {
    try await LinkedWorkspaceLoader(
      loader: WorkspaceLoader(),
      transformers: transformers ??
        TransformerLinkResolver(cancellation: { MockCancellation.never }),
      resolver: LinkResolver(),
    ).load(from: .workspace(workspace.folder.url))
  }

  private func useLinkProgram(responding response: String = Self.answer) throws {
    try workspace.writeLinksProgram(
      "tools/links",
      responding: response,
    )
    try workspace.folder.write("use-cases-bridge.yml", Self.linkBridge)
  }

  @Test
  func `a workspace with no bridge file loads`() async throws {
    #expect(try await load().resolution.links
      .map(\.key) == ["shop.cart.add#config@config/cart.yml:1"])
  }

  @Test
  func `a bridge file with validations only loads: they change neither links nor fingerprints`(
  ) async throws {
    try workspace.folder.write("use-cases-bridge.yml", BridgeFileSamples.validationsOnly)

    #expect(try await load().resolution.links.count == 1)
  }

  @Test
  func `a valid groups file does not stop the load, and is loaded with it`() async throws {
    try workspace.folder.write("use-case-groups.yml", "schema_version: 1\ngroups: {}\n")

    #expect(try await load().resolution.links.count == 1)
  }

  @Test
  func `the links a link transformer returns join the workspace's own`() async throws {
    try useLinkProgram()

    let linked = try await load()

    #expect(
      linked.resolution.links.map(\.key) == [
        "shop.cart.add#config@config/cart.yml:1",
        "shop.pay.card#unit-tests.charges@src/pay.swift:1",
      ],
    )
    #expect(linked.resolution.links.map(\.source) == [.manual, .transformer])
    #expect(linked.resolution.warningLines == ["use-cases-bridge.yml: tools/links: read 1 test"])
  }

  @Test
  func `a transformer that cannot answer stops the load as invalid, naming it`() async throws {
    try workspace.folder.writeProgram("tools/links", "exit 3\n")
    try workspace.folder.write("use-cases-bridge.yml", Self.linkBridge)

    let error = await #expect(throws: LinkedWorkspaceError.self) {
      try await load()
    }

    #expect(error?.refusalKind == .invalid)
    #expect(error?.message == "tools/links exited 3")
  }

  @Test
  func `a transformer stopped by a cancellation is no refusal`() async {
    let cancelled = MockTransformerLinks.failing(.cancelled)

    let error = await #expect(throws: LinkedWorkspaceError.self) {
      try await load(transformers: cancelled)
    }

    #expect(error == .transformerFailed(.cancelled))
    #expect(error?.refusalKind == nil)
  }

  @Test
  func `a workspace that does not load is refused before any transformer is asked`() async {
    let refusal = WorkspaceLoadingError.schemasUnavailable(message: "no schemas")
    let asked = MockTransformerLinks { _ in
      Issue.record("the transformers were asked")
      return .success(.none)
    }

    await #expect(throws: LinkedWorkspaceError.notLoaded(refusal)) {
      try await LinkedWorkspaceLoader(
        loader: MockWorkspaceLoading(refusal),
        transformers: asked,
        resolver: LinkResolver(),
      ).load(from: .workspace(workspace.folder.url))
    }
  }

  @Test
  func `the transformers are asked about the workspace that loaded`() async throws {
    let asked = MockTransformerLinks { loaded in
      #expect(loaded.summary.useCases == 5)
      return .success(.none)
    }

    _ = try await load(transformers: asked)
  }

  @Test
  func `a problem in the bridge file is refused as invalid before a transformer runs`(
  ) async throws {
    let ran = workspace.folder.url.deletingLastPathComponent()
      .appendingPathComponent("ran-\(UUID().uuidString)")
    defer {
      try? FileManager.default.removeItem(at: ran)
    }

    try workspace.folder.writeProgram("tools/links", "touch '\(ran.path)'\n")
    try workspace.folder.write(
      "use-cases-bridge.yml",
      Self.linkBridge + "validations:\n  - id: record\n    transformer: junit\n",
    )

    let error = await #expect(throws: LinkedWorkspaceError.self) {
      try await load()
    }

    #expect(error?.refusalKind == .invalid)
    #expect(error?.message.contains("validations/0/id") == true)
    #expect(!FileManager.default.fileExists(atPath: ran.path))
  }

  @Test
  func `a link problem is refused as invalid once the transformers have answered`() async throws {
    try useLinkProgram()
    try workspace.folder.write("src/a.swift", "// \(MarkerText.sentinel)shop.pay#top\nwork()\n")

    let error = await #expect(throws: LinkedWorkspaceError.self) {
      try await load()
    }

    #expect(error?.refusalKind == .invalid)
    #expect(error?.message.hasPrefix("src/a.swift:1: ") == true)
  }

  @Test
  func `a binding a marker and a transformer both name is refused as invalid`() async throws {
    try useLinkProgram()
    try workspace.folder.write(
      "src/a.swift",
      LinksWorkspace.marked("shop.pay.card#unit-tests.charges"),
    )

    let error = await #expect(throws: LinkedWorkspaceError.self) {
      try await load()
    }

    #expect(error?.refusalKind == .invalid)
    #expect(error?.message.contains("claimed by markers") == true)
    #expect(error?.message.contains("a links transformer (src/pay.swift:1)") == true)
  }

  // MARK: - Every command that loads the workspace

  @Test(arguments: [
    ["validate"],
    ["--json", "validate"],
    ["links"],
    ["links", "shop.pay"],
    ["--json", "links"],
    ["record", "shop.pay.card", "unit-tests", "pass"],
  ])
  func `validate, links and record run the link transformers`(arguments: [String]) async throws {
    try useLinkProgram()

    let result = await workspace.run(arguments)

    #expect(result.exitCode == 0)
    #expect(result.standardError.isEmpty)
  }

  @Test
  func `links lists a transformer's link with the source transformer`() async throws {
    try useLinkProgram()

    let document = try await workspace.run(["--json", "links"]).document()
    let links = try #require(document["links"])

    guard case let .array(entries) = links else {
      Issue.record("links is not a list")
      return
    }

    let transformed = entries.filter { entry in
      entry["source"] == .string("transformer")
    }
    let link = try #require(transformed.first)

    #expect(transformed.count == 1)
    #expect(link["key"] == .string("shop.pay.card#unit-tests.charges@src/pay.swift:1"))
    #expect(link["range"]?["end"] == .integer(2))
    #expect(
      document["diagnostics"]
        == .array([.string("use-cases-bridge.yml: tools/links: read 1 test")]),
    )
  }

  @Test(arguments: ["validate", "links"])
  func `a transformer that fails refuses the command as invalid and names the transformer`(
    command: String,
  ) async throws {
    try workspace.folder.writeProgram("tools/links", "echo no good\nexit 3\n")
    try workspace.folder.write("use-cases-bridge.yml", Self.linkBridge)

    let result = await workspace.run(["--json", command])
    let error = try #require(try result.document()["error"])

    #expect(result.exitCode == 2)
    #expect(result.standardOutput.contains("\"kind\" : \"invalid\""))
    #expect(error["message"] == .string("tools/links exited 3: no good"))
    #expect(result.standardError == "error: tools/links exited 3: no good\n")
  }

  @Test
  func `a transformer program that cannot be launched is a clear refusal`() async throws {
    try workspace.folder.write("tools/links", "#!/bin/sh\n")
    try workspace.folder.write("use-cases-bridge.yml", Self.linkBridge)

    let result = await workspace.run(["validate"])

    #expect(result.exitCode == 2)
    #expect(result.standardOutput.isEmpty)
    #expect(result.standardError.hasPrefix("error: tools/links could not be launched: "))
  }

  @Test
  func `a cancelled run exits 130 with one line, and no document unless it asked for one`()
    async throws
  {
    let runner = CommandLineRunner(
      loader: WorkspaceLoader(),
      transformers: MockTransformerLinks.failing(.cancelled),
      workingDirectory: workspace.folder.url,
    )

    let plain = await runner.run(arguments: ["links"])
    let json = await runner.run(arguments: ["--json", "links"])

    #expect(plain.exitCode == 130)
    #expect(plain.standardOutput.isEmpty)
    #expect(plain.standardError == "use-cases links: cancelled\n")
    #expect(json.exitCode == 130)
    #expect(json.standardError == "use-cases links: cancelled\n")
    #expect(try json.document()["error"]?["kind"] == .string("cancelled"))
  }

  @Test(arguments: [["links"], ["--json", "links"]])
  func `links answers a workspace whose bridge file has only validations`(
    arguments: [String],
  ) async throws {
    try workspace.folder.write("use-cases-bridge.yml", BridgeFileSamples.validationsOnly)

    let result = await workspace.run(arguments)

    #expect(result.exitCode == 0)
    #expect(result.standardError.isEmpty)
  }

  @Test
  func `record answers a workspace whose bridge file has only validations`() async throws {
    try workspace.folder.write("use-cases-bridge.yml", BridgeFileSamples.validationsOnly)

    let result = await workspace.run(["record", "shop.pay.card", "unit-tests", "pass", "--quiet"])

    #expect(result.exitCode == 0)
    #expect(result.standardOutput == "recorded: shop.pay.card / unit-tests → pass\n")
  }

  @Test
  func `a bridge file's validations change no fingerprint, so a verdict records the same one`(
  ) async throws {
    let before = try await workspace.run([
      "--json",
      "record",
      "shop.pay.card",
      "unit-tests",
      "pass",
    ])
    .document()
    try workspace.folder.write("use-cases-bridge.yml", BridgeFileSamples.validationsOnly)
    let after = try await workspace.run(["--json", "record", "shop.pay.card", "unit-tests", "pass"])
      .document()

    func fingerprint(_ document: JSONValue) -> JSONValue? {
      guard case let .array(results)? = document["results"] else {
        return nil
      }

      return results.first?["fingerprint"]
    }

    #expect(fingerprint(before) != nil)
    #expect(fingerprint(before) == fingerprint(after))
  }

  @Test(arguments: ["validate", "links"])
  func `a bridge file with a problem is refused as invalid, with the message of the problem`(
    command: String,
  ) async throws {
    try workspace.folder.write("use-cases-bridge.yml", Self.linkBridge + "extras: 1\n")

    let result = await workspace.run(["--json", command])

    #expect(result.exitCode == 2)
    #expect(try result.document()["error"]?["kind"] == .string("invalid"))
    #expect(result.standardError.contains("use-cases-bridge.yml: "))
  }

  @Test(arguments: ["validate", "links"])
  func `an invalid workspace is still refused first`(command: String) async throws {
    try workspace.folder.write("use-cases-bridge.yml", Self.linkBridge)
    try workspace.folder.write("src/a.swift", "// \(MarkerText.sentinel)shop.pay#top\nwork()\n")

    let result = await workspace.run([command])

    #expect(result.exitCode == 2)
  }
}

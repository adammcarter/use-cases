import Foundation
import Testing
import UseCasesTestSupport
@testable import UseCasesCore

struct TransformerLinkResolverTests {
  private static let bridge = """
  schema_version: 1
  links:
    - transformer: tools/links
      settings: { files: "test/**/*.js", strict: true }
    - transformer: test-names
  """

  private static let first = #"""
  {"contract":1,"links":[
    {"use_case":"app.toggle","binding":"render","role":"implementation","file":"src/math.js"},
    {"use_case":"app.toggle","route":"manual","binding":"renders","role":"validation",
     "file":"src/math.js","range":{"start":2,"end":3}}],
   "diagnostics":["read 2 tests"]}
  """#

  private static let second = #"""
  {"contract":1,"links":[
    {"use_case":"app.toggle","binding":"helper","role":"implementation","file":"src/other.js"}],
   "diagnostics":["looked at one file", "found nothing else"]}
  """#

  private let fixture: WorkspaceFixture

  init() throws {
    fixture = try WorkspaceFixture()
    try fixture.writeUseCase()
    try fixture.write("src/math.js", "one\ntwo\nthree\n")
    try fixture.write("src/other.js", "x\n")
    try fixture.write("tools/links", "#!/bin/sh\n")
    try fixture.write("use-cases-bridge.yml", Self.bridge)
  }

  private func resolver(
    runner: MockTransformerRunner,
    cancellation: any CancellationObserving = MockCancellation.never,
  ) -> TransformerLinkResolver {
    let fileSystem = LocalFileSystem()

    return TransformerLinkResolver(
      makeRunner: { _ in runner },
      cancellation: ObservedCancellationScope(makeObserver: { cancellation }),
      requestBuilder: LinksRequestBuilder(),
      responseReader: LinksResponseReader(),
      linkChecker: TransformerLinkChecker(
        placer: ManualBindingResolver(
          fileSystem: fileSystem,
          pathFinder: ExactPathFinder(fileSystem: fileSystem),
          rangeConverter: ManualRangeConverter(),
        ),
      ),
    )
  }

  private func answers(_ texts: String...) throws -> [Result<AuthoredValue, TransformerError>] {
    try texts.map { text in
      try .success(.json(text))
    }
  }

  @Test
  func `a workspace with no link transformer starts nothing`() async throws {
    try fixture.write("use-cases-bridge.yml", BridgeFileSamples.validationsOnly)
    let none = TransformerLinkResolver(
      makeRunner: { _ in
        Issue.record("a runner was made")
        return MockTransformerRunner(answers: [])
      },
      cancellation: ObservedCancellationScope(makeObserver: { MockCancellation.never }),
      requestBuilder: LinksRequestBuilder(),
      responseReader: LinksResponseReader(),
      linkChecker: NeverCalledLinkChecker(),
    )

    let found = try await none.links(for: fixture.loaded())

    #expect(found == .none)
  }

  @Test
  func `a workspace with no bridge file starts nothing`() async throws {
    try FileManager.default.removeItem(at: fixture.directory.location(of: "use-cases-bridge.yml"))
    let none = TransformerLinkResolver(
      makeRunner: { _ in
        Issue.record("a runner was made")
        return MockTransformerRunner(answers: [])
      },
      cancellation: ObservedCancellationScope(makeObserver: { MockCancellation.never }),
      requestBuilder: LinksRequestBuilder(),
      responseReader: LinksResponseReader(),
      linkChecker: NeverCalledLinkChecker(),
    )

    #expect(try await none.links(for: fixture.loaded()) == .none)
  }

  @Test
  func `the cancellation is made only when a transformer has to run`() async throws {
    try fixture.write("use-cases-bridge.yml", BridgeFileSamples.validationsOnly)
    let resolver = TransformerLinkResolver(
      cancellation: {
        Issue.record("a cancellation was made, and so a signal taken over")
        return MockCancellation.never
      },
    )

    #expect(try await resolver.links(for: fixture.loaded()) == .none)
  }

  @Test
  func `a real program is run when one is configured, and its links come back`() async throws {
    try fixture.write("src/other.js", "x\n")
    try fixture.directory.writeProgram(
      "tools/links",
      """
      printf '{"contract":1,"links":[{"use_case":"app.toggle","binding":"helper",\
      "role":"implementation","file":"src/other.js"}],"diagnostics":[]}' > "$3"
      """,
    )
    try fixture.write(
      "use-cases-bridge.yml",
      "schema_version: 1\nlinks:\n  - transformer: tools/links\n",
    )
    let resolver = TransformerLinkResolver(cancellation: { MockCancellation.never })

    let found = try await resolver.links(for: fixture.loaded())

    #expect(found.findings.links.map(\.key) == ["app.toggle#helper@src/other.js:1"])
  }

  @Test
  func `each transformer is asked in turn, with its own settings, and the links come in that order`(
  )
    async throws
  {
    let runner = try MockTransformerRunner(answers: answers(Self.first, Self.second))

    let found = try await resolver(runner: runner).links(for: fixture.loaded())
    let calls = await runner.calls

    #expect(
      found.findings.links.map(\.key) == [
        "app.toggle#render@src/math.js:1",
        "app.toggle#manual.renders@src/math.js:2",
        "app.toggle#helper@src/other.js:1",
      ],
    )
    #expect(found.findings.links.allSatisfy { $0.source == .transformer })
    #expect(calls.map(\.reference.name) == ["tools/links", "test-names"])
    #expect(calls.map(\.job) == [.links, .links])
  }

  @Test
  func `the request of an entry carries that entry's settings`() async throws {
    let runner = try MockTransformerRunner(answers: answers(Self.first, Self.second))

    _ = try await resolver(runner: runner).links(for: fixture.loaded())

    let calls = await runner.calls
    let settings = calls.map { call in
      StoreJSONWriter().compact(call.request).utf8Text
    }

    #expect(settings[0].contains(#""settings":{"files":"test/**/*.js","strict":true}"#))
    #expect(settings[1].contains(#""settings":{}"#))
  }

  @Test
  func `what a transformer says becomes a warning that names it, and decides nothing`(
  ) async throws {
    let runner = try MockTransformerRunner(answers: answers(Self.first, Self.second))

    let found = try await resolver(runner: runner).links(for: fixture.loaded())

    #expect(
      found.findings.diagnostics.map(\.description) == [
        "use-cases-bridge.yml: tools/links: read 2 tests",
        "use-cases-bridge.yml: test-names: looked at one file",
        "use-cases-bridge.yml: test-names: found nothing else",
      ],
    )
    #expect(found.findings.diagnostics.allSatisfy { $0.severity == .warning })
  }

  @Test
  func `a transformer that gives no answer stops the rest and fails the whole job`() async throws {
    let runner = MockTransformerRunner(
      answers: [.failure(.timedOut(name: "tools/links", after: .seconds(120)))],
    )

    let error = await #expect(throws: TransformerLinkingError.self) {
      try await resolver(runner: runner).links(for: fixture.loaded())
    }

    #expect(error == .failed(message: "tools/links did not finish within 120 seconds"))
    #expect(await runner.calls.count == 1)
  }

  @Test
  func `a signal that comes after the last answer is still a cancellation`() async throws {
    let runner = try MockTransformerRunner(answers: answers(Self.first, Self.second))

    let error = await #expect(throws: TransformerLinkingError.self) {
      try await resolver(
        runner: runner,
        cancellation: MockCancellation.always,
      ).links(for: fixture.loaded())
    }

    #expect(error == .cancelled)
  }

  @Test
  func `a cancellation is a cancellation`() async throws {
    let runner = MockTransformerRunner(answers: [.failure(.cancelled)])

    let error = await #expect(throws: TransformerLinkingError.self) {
      try await resolver(runner: runner).links(for: fixture.loaded())
    }

    #expect(error == .cancelled)
  }

  @Test
  func `a link that cannot be placed fails the job and names the transformer and the link`()
    async throws
  {
    let runner = try MockTransformerRunner(
      answers: answers(
        #"""
        {"contract":1,"diagnostics":[],"links":[
          {"use_case":"app.toggle","binding":"x","role":"implementation","file":"src/gone.js"}]}
        """#,
      ),
    )

    let error = await #expect(throws: TransformerLinkingError.self) {
      try await resolver(runner: runner).links(for: fixture.loaded())
    }

    guard case let .failed(message)? = error else {
      Issue.record("not a failure: \(String(describing: error))")
      return
    }

    #expect(message.hasPrefix("tools/links returned a bad link {"))
    #expect(message.hasSuffix("the file 'src/gone.js' does not exist"))
  }

  @Test
  func `the more specific error wins: a bad link is told before a missing diagnostics`(
  ) async throws {
    let runner = try MockTransformerRunner(
      answers: answers(
        #"""
        {"contract":1,"links":[
          {"use_case":"app.nope","binding":"x","role":"implementation","file":"src/math.js"}]}
        """#,
      ),
    )

    let error = await #expect(throws: TransformerLinkingError.self) {
      try await resolver(runner: runner).links(for: fixture.loaded())
    }

    #expect(error?.message.contains("unknown use case 'app.nope'") == true)
  }

  @Test
  func `a response with no diagnostics is malformed once its links are fine`() async throws {
    let runner = try MockTransformerRunner(answers: answers(#"{"contract":1,"links":[]}"#))

    let error = await #expect(throws: TransformerLinkingError.self) {
      try await resolver(runner: runner).links(for: fixture.loaded())
    }

    #expect(
      error
        == .failed(
          message: "tools/links wrote malformed output: diagnostics: this is required",
        ),
    )
  }

  @Test
  func `a response with no links is malformed`() async throws {
    let runner = try MockTransformerRunner(answers: answers(#"{"contract":1,"diagnostics":[]}"#))

    let error = await #expect(throws: TransformerLinkingError.self) {
      try await resolver(runner: runner).links(for: fixture.loaded())
    }

    #expect(
      error
        == .failed(message: "tools/links wrote malformed output: links: this is required"),
    )
  }
}

/// A checker that is never asked.
private struct NeverCalledLinkChecker: TransformerLinkChecking {
  func resolve(
    _ link: TransformerLink,
    from name: String,
    among targets: LinkTargets,
    context: DiscoveryContext,
    files: inout BoundFiles,
  ) throws(TransformerError) -> ResolvedLink {
    throw .cancelled
  }
}

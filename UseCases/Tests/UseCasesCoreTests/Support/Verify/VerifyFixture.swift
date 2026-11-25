import Foundation
import Testing
import UseCasesTestSupport
@testable import UseCasesCore

/// A workspace on disk with the sample use case `app.toggle`, one validation `unit-tests` whose
/// report is `unit.xml`, a test and the code it tests linked by markers, and the real pieces of
/// `verify` over it, with a clock and random bits the test fixes.
struct VerifyFixture {
  static let validation = "unit-tests"
  static let testFile = "tests/t.swift"
  static let codeFile = "src/app.swift"

  let freshness: FreshnessFixture
  let store: VerifyStore
  let clock = FixedTimekeeper()

  var workspace: URL {
    freshness.workspace.directory.url
  }

  /// - Parameter bridge: The text of `use-cases-bridge.yml`; `nil` writes none.
  init(
    bridge: String? = BridgeFileSamples.validation(lines: ["report: unit.xml"]),
    definitions: String = FreshnessSamples.definitions(),
  ) throws {
    freshness = try FreshnessFixture(definitions: definitions)

    try freshness.write(
      Self.testFile,
      LinkSamples.marked("app.toggle#unit-tests.renders", "check()"),
    )
    try freshness.write(
      Self.codeFile,
      LinkSamples.marked("app.toggle#draw", "draw()"),
    )

    if let bridge {
      try freshness.write("use-cases-bridge.yml", bridge)
    }

    let access = StoreFileAccess(
      fileSystem: LocalFileSystem(),
      json: JSONReader(),
    )

    store = try VerifyStore(
      writer: RunWriter(
        clock: clock,
        random: FixedRandomBits(),
      ),
      finder: OpenRunFinder(
        access: access,
        checker: BundledStoreSchemaLoader().loadChecker(
          for: .start,
          unknownMembers: .ignore,
        ),
      ),
      access: access,
      locks: FlockRunLock(),
    )
  }

  /// The workspace as it is on disk now, with its links.
  func resolved() throws -> ResolvedWorkspace {
    let loaded = try freshness.workspace.loaded()

    return ResolvedWorkspace(
      workspace: loaded,
      links: LinkResolver().resolveLinks(in: loaded),
    )
  }

  /// The key of the validation link of `unit-tests`.
  func linkKey() throws -> String {
    let links = try resolved().links.links.filter { link in
      link.role == .validation
    }

    return try #require(links.first).key
  }

  func starter() -> VerifyStarter {
    VerifyStarter(
      fingerprinter: RouteFingerprintComputer(),
      store: .success(store),
      digester: ValidationsDigester(),
    )
  }

  func aborter() -> VerifyAborter {
    VerifyAborter(store: .success(store))
  }

  /// The finish point over the fixture's store, with `runner` for transformers and `cancellation`
  /// watching them.
  func finishPoint(
    runner: any TransformerRunning,
    cancellation: any CancellationObserving = MockCancellation.never,
  ) -> FinishPoint {
    FinishPoint(
      store: store,
      sources: SourceReader(access: store.access),
      judge: RouteJudge(),
      digester: ValidationsDigester(),
      fingerprinter: RouteFingerprintComputer(),
      makeRunner: { _ in runner },
      cancellation: ObservedCancellationScope(makeObserver: { cancellation }),
      clock: clock,
    )
  }

  /// A finisher whose transformers are `runner`, run with `cancellation` watching them.
  func finisher(
    runner: any TransformerRunning,
    cancellation: any CancellationObserving = MockCancellation.never,
  ) -> VerifyFinisher {
    VerifyFinisher(
      store: .success(store),
      finishPoint: .success(
        finishPoint(
          runner: runner,
          cancellation: cancellation,
        ),
      ),
    )
  }

  /// Starts a run over every validation.
  @discardableResult
  func start(only: [String] = []) throws -> StartedVerifyRun {
    try starter().start(
      VerifyStartRequest(only: only),
      in: resolved(),
    )
  }

  /// What the tests write into a started run's report.
  func writeReport(
    of started: StartedVerifyRun,
    _ text: String = "<testsuites/>",
  ) throws {
    let file = try URL(fileURLWithPath: #require(started.reports.first).path)

    try FileManager.default.createDirectory(
      at: file.deletingLastPathComponent(),
      withIntermediateDirectories: true,
    )
    try Data(text.utf8).write(to: file)
  }

  /// The text of a file of the workspace.
  func read(_ path: String) throws -> String {
    try String(
      contentsOf: freshness.workspace.directory.location(of: path),
      encoding: .utf8,
    )
  }

  /// The run folders in the store, sorted.
  func runs() -> [String] {
    let found = (try? FileManager.default.contentsOfDirectory(
      atPath: freshness.workspace.directory.location(of: ".use-cases/runs").path,
    )) ?? []

    return found.sorted()
  }

  /// The folder of a run in the store.
  func runFolder(_ run: String) -> URL {
    freshness.workspace.directory.location(of: ".use-cases/runs/\(run)")
  }

  /// Adds text to the end of a run's log, as a finish that stopped partway would have left it.
  func stage(
    _ text: String,
    in run: String,
  ) throws {
    let handle = try FileHandle(forWritingTo: runFolder(run)
      .appendingPathComponent("results.jsonl"))
    defer {
      try? handle.close()
    }

    try handle.seekToEnd()
    try handle.write(contentsOf: Data(text.utf8))
  }

  /// A whole line of the log, a verdict for `unit-tests` that would count if it stayed.
  func stagedResultLine() throws -> String {
    let result = try StoredResult(
      useCase: .sample("app.toggle"),
      route: .sample("unit-tests"),
      fingerprint: .sample("a"),
      verdict: .pass,
      detail: StoredResultDetail(
        recordedAt: StoreSamples.timestamp,
        origin: .validations(
          [IdentifierSegment(validating: Self.validation)],
          links: [LinkResult(key: linkKey(), verdict: .pass)],
        ),
        message: nil,
        attachments: [],
      ),
    )
    let document = try #require(result.document)

    return (String(bytes: StoreJSONWriter().compact(document), encoding: .utf8) ?? "") + "\n"
  }

  /// The history the real reader reads.
  func history() throws -> StoreHistory {
    try StoreReader().readHistory(in: workspace)
  }

  /// A response of a results transformer: one result per link key, and these unlinked tests.
  static func response(
    _ results: [String: String],
    diagnostics: [String] = [],
  ) throws -> AuthoredValue {
    var entries: [StoreJSONValue] = []

    for key in results.keys.sorted() {
      entries.append(
        .members([
          "link": .string(key),
          "status": .string(results[key] ?? "pass"),
          "tests": .strings(["t"]),
        ]),
      )
    }

    let response = StoreJSONValue.members([
      "contract": .integer(1),
      "results": .array(entries),
      "unlinked": .array([]),
      "diagnostics": .strings(diagnostics),
    ])

    return try .json(String(bytes: StoreJSONWriter().compact(response), encoding: .utf8) ?? "")
  }
}

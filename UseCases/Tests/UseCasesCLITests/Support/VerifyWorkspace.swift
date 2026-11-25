import Foundation
import UseCasesCore
import UseCasesTestSupport
@testable import UseCasesCLI

/// A shop on disk with one use case, `shop.pay.card`, whose route `unit-tests` is linked to a
/// test, and a bridge file with one validation, `unit-tests`, whose results transformer is a
/// program of the project that reports a `pass` for every link of the request.
struct VerifyWorkspace {
  static let passingTransformer = """
  keys=$(sed -n 's/^ *"key": "\\(.*\\)",*$/\\1/p' "$2")
  printf '{"contract":1,"results":[' > "$3"
  separator=""
  for key in $keys; do
    printf '%s{"link":"%s","status":"pass"}' "$separator" "$key" >> "$3"
    separator=","
  done
  printf '],"unlinked":[],"diagnostics":[]}' >> "$3"

  """

  let folder: TemporaryFolder

  init(
    bridge: String? = Self.bridge,
    transformer: String = Self.passingTransformer,
  ) throws {
    folder = try TemporaryFolder()

    try folder.write("use-cases.yml", "schema_version: 1\nroot: true\nprefix: shop\n")
    try folder.write(
      "use-cases/pay.yml",
      """
      prefix: pay
      use_cases:
        - id: card
          title: Pay by card
          value_tier: core
          intent: A card payment is taken.
          scenarios:
            - id: works
              when: [x]
              then: [y]
          validation:
            - id: unit-tests
              type: { kind: unit }
              covers: [works]

      """,
    )
    try folder.write(
      "tests/pay.swift",
      "// \(MarkerText.sentinel)shop.pay.card#unit-tests.works\ncheck()\n"
        + "// \(MarkerText.sentinel)end shop.pay.card#unit-tests.works\n",
    )
    try folder.writeProgram("tools/results", transformer)

    if let bridge {
      try folder.write("use-cases-bridge.yml", bridge)
    }
  }

  static let bridge = """
  schema_version: 1
  validations:
    - id: unit-tests
      report: unit.xml
      transformer: tools/results

  """

  var url: URL {
    folder.url
  }

  /// A bridge file whose `unit-tests` runs `script` with `sh -c`; the script gets its report path
  /// as `$1`.
  static func bridge(running script: String) -> String {
    """
    schema_version: 1
    validations:
      - id: unit-tests
        report: unit.xml
        run: [sh, -c, '\(script)', sh, "{report}"]
        transformer: tools/results

    """
  }

  /// A bridge file whose `unit-tests` runs a command that is held on `hold` until the test lets
  /// it go. Keep the hold outside the workspace, where nothing of the product reads it.
  static func bridge(holdingOn hold: ChildHold) -> String {
    // The script goes between single quotes in YAML, where a quote is written twice.
    bridge(running: hold.shellText().replacingOccurrences(of: "'", with: "''"))
  }

  /// Runs the command line from the workspace root. No signal is taken over: `cancellation` says
  /// whether the request was cancelled, to the command and to everything it runs. The scope the
  /// command line holds is made of it, unless the test gives one, and so are the services of the
  /// steps the test wants to watch. `transformers`, left out, is the real links resolver;
  /// `clock` is what the runner's cancellation watcher waits on between looks, and left out is
  /// the runner's own default.
  func run(
    _ arguments: [String],
    scope: (any CancellationScoping)? = nil,
    cancellation: @escaping @Sendable () -> any CancellationObserving = { MockCancellation.never },
    loader: any WorkspaceLoading = WorkspaceLoader(),
    transformers: (any TransformerLinkProviding)? = nil,
    starter: any VerifyStarting = VerifyStarter(),
    aborter: any VerifyAborting = VerifyAborter(),
    recorder: any VerdictRecording = VerdictRecorder(),
    prompter: any Prompting = MockPrompter(),
    isTerminal: Bool = false,
    deliver: @escaping @Sendable (CommandResult) async -> Void = { _ in },
    clock: (any Clock<Duration>)? = nil,
  ) async -> CommandResult {
    let transformers = transformers ?? TransformerLinkResolver(cancellation: cancellation)
    let verifier = Verifier(
      starter: starter,
      finisher: VerifyFinisher(cancellation: cancellation),
      runner: VerifyRunner(cancellation: cancellation),
      aborter: aborter,
    )
    let scope = scope ?? ObservedCancellationScope(makeObserver: cancellation)

    guard let clock else {
      return await CommandLineRunner(
        loader: loader,
        transformers: transformers,
        recorder: recorder,
        prompter: prompter,
        verifier: verifier,
        cancellation: scope,
        deliver: deliver,
        isTerminal: isTerminal,
        workingDirectory: folder.url,
      ).run(arguments: arguments)
    }

    return await CommandLineRunner(
      loader: loader,
      transformers: transformers,
      recorder: recorder,
      prompter: prompter,
      verifier: verifier,
      cancellation: scope,
      deliver: deliver,
      isTerminal: isTerminal,
      workingDirectory: folder.url,
      clock: clock,
    ).run(arguments: arguments)
  }

  /// Starts a run over every validation and returns its `--json` document.
  func start(_ extra: [String] = []) async throws -> JSONValue {
    try await run(["--json", "verify", "--start"] + extra).document()
  }

  /// What the tests write into a started run: a report at the path `--start` gave.
  func writeReport(of started: JSONValue) throws {
    guard case let .object(reports)? = started["reports"],
          case let .string(path)? = reports["unit-tests"]
    else {
      throw WorkspaceFailure(message: "no report path in the start document")
    }

    let file = URL(fileURLWithPath: path)

    try FileManager.default.createDirectory(
      at: file.deletingLastPathComponent(),
      withIntermediateDirectories: true,
    )
    try Data("<testsuites/>".utf8).write(to: file)
  }

  /// The text of a file below the workspace root.
  func read(_ path: String) throws -> String {
    try String(
      contentsOf: folder.url.appendingPathComponent(path),
      encoding: .utf8,
    )
  }

  /// The run folders in the store.
  func runs() -> [String] {
    let found = try? FileManager.default.contentsOfDirectory(
      atPath: folder.url.appendingPathComponent(".use-cases/runs").path,
    )

    return (found ?? []).sorted()
  }
}

/// A fixture that could not do what a test asked of it.
struct WorkspaceFailure: Error, CustomStringConvertible {
  let message: String

  var description: String {
    message
  }
}

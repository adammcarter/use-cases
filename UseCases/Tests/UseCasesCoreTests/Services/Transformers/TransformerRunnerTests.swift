import Foundation
import Testing
import UseCasesTestSupport
@testable import UseCasesCore

struct TransformerRunnerTests {
  static let validAnswer = #"printf '{"contract":1,"links":[],"diagnostics":[]}' > "$3""#

  private let workspace: TemporaryDirectory
  private let scratchParent: TemporaryDirectory

  init() throws {
    workspace = try TemporaryDirectory()
    scratchParent = try TemporaryDirectory()
  }

  /// A runner whose transformers run for real, through the real supervisor; each test's
  /// transformer ends by itself.
  func runner(executable: URL? = nil) -> TransformerRunner {
    runner(
      executable: executable,
      supervisor: ProcessSupervisor(cancellation: MockCancellation.never),
      timeout: .seconds(60),
    )
  }

  func run(
    _ body: String,
    request: StoreJSONValue = .members(["contract": .integer(1)]),
  ) async throws -> AuthoredObject {
    try await run(
      body,
      on: runner(),
      request: request,
    )
  }

  /// Runs the program `tools/transformer`, whose text is `body`, on `runner`.
  func run(
    _ body: String,
    on runner: TransformerRunner,
    request: StoreJSONValue = .members(["contract": .integer(1)]),
  ) async throws -> AuthoredObject {
    try workspace.writeProgram(
      "tools/transformer",
      body,
    )

    return try await runner.run(
      .program(WorkspacePath(validating: "tools/transformer")),
      job: .links,
      request: request,
      in: workspace.url,
    )
  }

  // MARK: - How it is started

  @Test
  func `the transformer starts in the workspace root, with the job and two files`() async throws {
    _ = try await run(
      """
      pwd -P > cwd.txt
      echo "$1" > job.txt
      echo "$#" > count.txt
      \(Self.validAnswer)
      """,
    )

    #expect(try workspace.text(of: "cwd.txt").trimmed == workspace.url.path)
    #expect(try workspace.text(of: "job.txt").trimmed == "links")
    #expect(try workspace.text(of: "count.txt").trimmed == "3")
  }

  @Test
  func `the request is the document the caller gave, and the response is a file beside it`()
    async throws
  {
    _ = try await run(
      """
      cp "$2" request-seen.json
      dirname "$2" > folder-of-request.txt
      dirname "$3" > folder-of-response.txt
      \(Self.validAnswer)
      """,
      request: .members(["contract": .integer(1), "job": .string("links")]),
    )

    let seen = try workspace.text(of: "request-seen.json")

    #expect(seen == "{\n  \"contract\": 1,\n  \"job\": \"links\"\n}\n")
    #expect(
      try workspace.text(of: "folder-of-request.txt") == workspace
        .text(of: "folder-of-response.txt"),
    )
  }

  @Test
  func `the private folder is outside the workspace and is for this user alone`() async throws {
    _ = try await run(
      """
      dirname "$2" > folder.txt
      ls -ld "$(dirname "$2")" | cut -c1-10 > mode.txt
      \(Self.validAnswer)
      """,
    )

    let folder = try workspace.text(of: "folder.txt").trimmed

    #expect(folder.hasPrefix(scratchParent.url.path))
    #expect(!folder.hasPrefix(workspace.url.path))
    #expect(try workspace.text(of: "mode.txt").trimmed == "drwx------")
  }

  @Test
  func `the private folder is removed afterwards, whatever the ending`() async throws {
    _ = try await run(Self.validAnswer)
    _ = try? await run("exit 3\n")
    _ = try? await run("kill -9 $$\n")
    _ = try? await run(
      Self.validAnswer,
      on: runner(
        supervisor: ScriptedProcessSupervisor(inOrder: [Self.timingOut]),
        timeout: .seconds(60),
      ),
    )
    _ = try? await run(
      Self.validAnswer,
      on: runner(
        supervisor: ScriptedProcessSupervisor(inOrder: [Self.cancelling]),
        timeout: .seconds(60),
      ),
    )

    #expect(try FileManager.default.contentsOfDirectory(atPath: scratchParent.url.path).isEmpty)
  }

  @Test
  func `an environment variable of the caller reaches the transformer`() async throws {
    _ = try await run(
      """
      echo "${HOME:-unset}" > home.txt
      \(Self.validAnswer)
      """,
    )

    #expect(try workspace.text(of: "home.txt").trimmed != "unset")
  }

  @Test
  func `a bundled transformer is started through the one program, with its name first`()
    async throws
  {
    try workspace.writeProgram(
      "bin/use-cases-transformers",
      """
      echo "$1 $2" > seen.txt
      printf '{"contract":1}' > "$4"
      """,
    )
    try workspace.write("bin/use-cases")

    let answer = try await runner(executable: workspace.location(of: "bin/use-cases")).run(
      .bundled("junit"),
      job: .results,
      request: .members(["contract": .integer(1)]),
      in: workspace.url,
    )

    #expect(try workspace.text(of: "seen.txt").trimmed == "junit results")
    #expect(try answer.requiredInteger("contract") == 1)
  }

  @Test
  func `a bundled transformer with no program beside use-cases starts nothing`() async throws {
    let missing = TransformerError.programMissing(
      name: "junit",
      expectedAt: "\(workspace.url.path)/bin/use-cases-transformers",
    )

    await #expect(throws: missing) {
      try await runner(executable: workspace.location(of: "bin/use-cases")).run(
        .bundled("junit"),
        job: .links,
        request: .members([:]),
        in: workspace.url,
      )
    }
  }

  // MARK: - How it ends

  @Test
  func `a program that is not executable could not be launched`() async throws {
    try workspace.write("tools/transformer", "#!/bin/sh\n")

    let error = await #expect(throws: TransformerError.self) {
      try await runner().run(
        .program(WorkspacePath(validating: "tools/transformer")),
        job: .links,
        request: .members([:]),
        in: workspace.url,
      )
    }

    guard case let .couldNotLaunch(name, reason)? = error else {
      Issue.record("not a launch failure: \(String(describing: error))")
      return
    }

    #expect(name == "tools/transformer")
    #expect(!reason.isEmpty)
  }

  @Test
  func `an exit code other than 0 is an error that carries the end of what it printed`() async {
    await #expect(
      throws: TransformerError.exited(name: "tools/transformer", code: 3, console: "bad\nthing"),
    ) {
      try await run("echo bad\necho thing >&2\nexit 3\n")
    }
  }

  @Test
  func `only the end of a long console is kept`() async throws {
    let error = await #expect(throws: TransformerError.self) {
      try await run(
        "i=0\nwhile [ $i -lt 100 ]; do echo \"line number $i\"; i=$((i+1)); done\nexit 2\n",
      )
    }

    guard case let .exited(_, _, console)? = error else {
      Issue.record("not an exit: \(String(describing: error))")
      return
    }

    #expect(console.count == TransformerRunner.consoleTailLength)
    #expect(console.hasSuffix("line number 99"))
  }

  @Test
  func `a signal that kills the transformer is an error`() async {
    await #expect(throws: TransformerError.signaled(name: "tools/transformer", signal: 9)) {
      try await run("kill -9 $$\n")
    }
  }

  /// The stopping itself, of the whole group, is the supervisor's, proven on real processes by
  /// `ProcessSupervisorTimeoutTests`.
  @Test
  func `a transformer that does not finish in its time is stopped, and the error says how long`()
    async
  {
    let supervisor = ScriptedProcessSupervisor(inOrder: [Self.timingOut])

    await #expect(
      throws: TransformerError.timedOut(name: "tools/transformer", after: .seconds(7)),
    ) {
      try await run(
        Self.validAnswer,
        on: runner(
          supervisor: supervisor,
          timeout: .seconds(7),
        ),
      )
    }

    #expect(await supervisor.requests.map(\.timeout) == [.seconds(7)])
  }

  @Test
  func `the time a transformer has is 120 seconds unless a test says otherwise`() {
    #expect(ProcessTimeout.transformer == .seconds(120))
  }

  /// The stopping itself is the supervisor's, proven on real processes by
  /// `ProcessSupervisorCancellationTests`.
  @Test
  func `a cancellation stops the transformer and is no failure of its own`() async {
    await #expect(throws: TransformerError.cancelled) {
      try await run(
        Self.validAnswer,
        on: runner(
          supervisor: ScriptedProcessSupervisor(inOrder: [Self.cancelling]),
          timeout: .seconds(60),
        ),
      )
    }
  }

  // MARK: - What it answers

  @Test
  func `an answer that says contract 1 is returned, and what it does not know is kept for later`()
    async throws
  {
    let answer = try await run(
      #"printf '{"contract":1,"links":[],"diagnostics":[],"added_later":{"a":[1]}}' > "$3""#,
    )

    #expect(try answer.requiredInteger("contract") == 1)
    #expect(answer.contains("added_later"))
  }

  @Test
  func `a contract written 1.0 is contract 1`() async throws {
    let answer = try await run(#"printf '{"contract":1.0}' > "$3""#)

    #expect(try answer.requiredInteger("contract") == 1)
  }

  @Test(
    arguments: [
      ("exit 0\n", "no response.json was written"),
      (#"printf 'not json' > "$3""#, "response.json is not JSON: unexpected character at offset 1"),
      (
        #"printf '{"contract":1' > "$3""#,
        "response.json is not JSON: the text ends before the document does",
      ),
      (
        #"printf '{"contract":1,"contract":1}' > "$3""#,
        "response.json is not JSON: duplicate key 'contract' at offset 14",
      ),
      (
        #"printf '' > "$3""#,
        "response.json is not JSON: the text ends before the document does",
      ),
      (#"printf '[1]' > "$3""#, "response.json is not a JSON object"),
      (#"printf '"text"' > "$3""#, "response.json is not a JSON object"),
      (#"printf '\377' > "$3""#, "response.json is not UTF-8 text"),
      (#"printf '{"contract":"1"}' > "$3""#, "contract: this must be a whole number"),
      (#"printf '{"contract":1.5}' > "$3""#, "contract: this must be a whole number"),
      (#"printf '{"contract":null}' > "$3""#, "contract: this must be a whole number"),
    ],
  )
  func `an answer that is no JSON object, or a contract of the wrong type, is malformed`(
    body: String,
    reason: String,
  ) async {
    await #expect(
      throws: TransformerError.malformedResponse(name: "tools/transformer", reason: reason),
    ) {
      try await run(body)
    }
  }

  @Test(
    arguments: [
      #"printf '{}' > "$3""#,
      #"printf '{"links":[]}' > "$3""#,
      #"printf '{"contract":2}' > "$3""#,
      #"printf '{"contract":0}' > "$3""#,
      #"printf '{"contract":-1}' > "$3""#,
    ],
  )
  func `a missing or other contract is not supported`(body: String) async {
    await #expect(throws: TransformerError.unsupportedContract(name: "tools/transformer")) {
      try await run(body)
    }
  }
}

extension TransformerRunnerTests {
  /// A runner whose transformers are answered by `supervisor`, with `timeout` to answer in.
  func runner(
    executable: URL? = nil,
    supervisor: any ProcessSupervising,
    timeout: Duration,
  ) -> TransformerRunner {
    TransformerRunner(
      locator: TransformerLocator(
        executable: StubExecutable(location: executable),
        fileSystem: LocalFileSystem(),
      ),
      scratchMaker: TransformerScratchMaker(parent: scratchParent.url),
      supervisor: supervisor,
      jsonReader: JSONReader(),
      jsonWriter: StoreJSONWriter(),
      timeout: timeout,
    )
  }

  /// A scripted transformer still running when the time it was given is up.
  private static let timingOut: ScriptedProcessSupervisor.Step = { request in
    ScriptedProcessSupervisor.ended(.timedOut(after: request.timeout))
  }

  /// A scripted transformer stopped by a cancellation while it runs.
  private static let cancelling = ScriptedProcessSupervisor.answering(
    ScriptedProcessSupervisor.ended(.cancelled),
  )
}

extension String {
  var trimmed: String {
    trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

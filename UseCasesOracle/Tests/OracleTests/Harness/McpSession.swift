import Foundation

/// Driving the MCP server over stdio, for the black-box oracle.
///
/// The CLI half of the oracle reaches the binary through ``CliBinary``; this is
/// the other half, and it is the Swift shape of `tests/helpers/mcp-server.ts`:
/// one process per session, newline-framed JSON-RPC on its stdin and stdout,
/// one request/response round trip per call, ids matched across interleaved
/// lines, and a 15 second ceiling on any one request.
///
/// `UC_MCP_BIN` is the seam, mirroring `UC_BIN`: unset it runs the Swift build,
/// set it runs whatever it names.
///
/// An actor, because the pending table is written by the reader task and by
/// every caller. Nothing here polls or sleeps waiting for a line: stdout
/// chunks arrive on an `AsyncStream` fed by the pipe's readability handler, and
/// a caller suspends on a continuation until its own id comes back.
actor McpSession {
  static let environmentVariable = "UC_MCP_BIN"
  static let requestTimeoutSeconds = 15

  private let process: Process
  private let input: FileHandle
  private let output: FileHandle
  private let errors: FileHandle
  /// Yields once, with the exit status, when the server process ends.
  private let terminations: AsyncStream<Int32>
  private var pending: [Int: CheckedContinuation<JsonRpcResponse, Error>] = [:]
  private var buffer = Data()
  private var nextIdentifier = 1
  private var reader: Task<Void, Never>?
  private var ended = false

  struct JsonRpcResponse: Sendable {
    let json: OracleJson

    var identifier: Int? {
      json["id"]?.intValue
    }

    var result: OracleJson? {
      json["result"]
    }

    var error: OracleJson? {
      json["error"]
    }

    var errorCode: Int? {
      json.at("error.code")?.intValue
    }

    var errorMessage: String? {
      json.at("error.message")?.stringValue
    }
  }

  /// A tool call's answer: the JSON-RPC frame, and the v1 CLI envelope parsed
  /// out of its text content. The whole point of the wrapper is that this is
  /// the SAME envelope the CLI emits.
  struct ToolOutcome: Sendable {
    let envelope: CliBinary.Envelope
    let raw: JsonRpcResponse

    var data: OracleJson {
      envelope.data
    }

    var isOk: Bool? {
      envelope.isOk
    }

    var diagnosticCodes: [String] {
      envelope.diagnosticCodes
    }
  }

  /// Where the server binary is, by the same rule ``CliBinary`` follows.
  static func resolvedBinary(override: String?) throws -> String {
    let named = override?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !named.isEmpty {
      guard FileManager.default.isExecutableFile(atPath: named) else {
        throw OracleFailure.binaryUnusable(variable: environmentVariable, path: named)
      }
      return named
    }
    guard
      let built = OracleLayout.builtBinary(package: "UseCasesMCP", named: "use-cases-mcp")
    else {
      throw OracleFailure.binaryMissing(
        name: "use-cases-mcp",
        searched: OracleLayout.buildDirectories(package: "UseCasesMCP"),
        variable: environmentVariable,
      )
    }
    return built
  }

  static func resolvedBinary() throws -> String {
    try resolvedBinary(override: ProcessInfo.processInfo.environment[environmentVariable])
  }

  /// Start a session and complete the initialize handshake.
  static func start(
    cwd: String,
    environment: [String: String] = [:],
  ) async throws -> McpSession {
    let session = try McpSession(cwd: cwd, environment: environment)
    await session.startReading()
    _ = try await session.request(
      "initialize",
      params: .object([
        "protocolVersion": .string("2024-11-05"),
        "capabilities": .object([:]),
        "clientInfo": .object([
          "name": .string("use-cases-blackbox"),
          "version": .string("0"),
        ]),
      ]),
    )
    return session
  }

  private init(
    cwd: String,
    environment: [String: String],
  ) throws {
    let binary = try McpSession.resolvedBinary()
    process = Process()
    process.executableURL = URL(fileURLWithPath: binary)
    process.arguments = []
    process.currentDirectoryURL = URL(fileURLWithPath: cwd)
    process.environment = OracleProcess.inherited(environment)
    let stdin = Pipe()
    let stdout = Pipe()
    let stderr = Pipe()
    process.standardInput = stdin
    process.standardOutput = stdout
    process.standardError = stderr
    input = stdin.fileHandleForWriting
    output = stdout.fileHandleForReading
    errors = stderr.fileHandleForReading
    let (stream, continuation) = AsyncStream.makeStream(of: Int32.self)
    terminations = stream
    process.terminationHandler = { finished in
      continuation.yield(finished.terminationStatus)
      continuation.finish()
    }
    // stdout arrives as chunks, exactly as `child.stdout.on("data")` delivers
    // them: the handler is called by the system when bytes are ready, so no
    // task ever sits in a blocking read. (`FileHandle.bytes` was measured to
    // do exactly that, and a dozen parallel sessions then starve the
    // cooperative pool and every request times out.)
    let (chunkStream, chunkContinuation) = AsyncStream.makeStream(of: Data.self)
    chunks = chunkStream
    output.readabilityHandler = { handle in
      let data = handle.availableData
      if data.isEmpty {
        handle.readabilityHandler = nil
        chunkContinuation.finish()
      } else {
        chunkContinuation.yield(data)
      }
    }
    // stderr is drained and dropped: a server that logs more than a pipe holds
    // would otherwise block on a write nobody reads.
    errors.readabilityHandler = { handle in
      if handle.availableData.isEmpty {
        handle.readabilityHandler = nil
      }
    }
    try process.run()
  }

  private let chunks: AsyncStream<Data>

  private func startReading() {
    reader = Task { [weak self, chunks] in
      for await chunk in chunks {
        await self?.consume(chunk)
      }
      await self?.finishPending()
    }
  }

  /// Newline framing, one response per line, ids matched across interleaved
  /// lines — the discipline `mcp-server.ts` keeps.
  ///
  /// The buffer is bytes, not text: a chunk boundary can fall inside a
  /// multi-byte character, and decoding each chunk on arrival would turn that
  /// into replacement characters. A newline never falls inside one, so every
  /// line is decoded whole.
  private func consume(_ chunk: Data) {
    buffer.append(chunk)
    while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
      let raw = buffer[buffer.startIndex ..< newline]
      buffer = Data(buffer[buffer.index(after: newline)...])
      let line = (String(bytes: raw, encoding: .utf8) ?? "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
      guard !line.isEmpty else {
        continue
      }
      // Not every line on stdout is a response; ignore the rest.
      guard let parsed = try? OracleJson.parse(line) else {
        continue
      }
      let response = JsonRpcResponse(json: parsed)
      guard let identifier = response.identifier,
            let continuation = pending.removeValue(forKey: identifier)
      else {
        continue
      }
      continuation.resume(returning: response)
    }
  }

  private func finishPending() {
    ended = true
    let waiting = pending
    pending.removeAll()
    for continuation in waiting.values {
      continuation.resume(throwing: OracleFailure.serverEnded(method: "a pending request"))
    }
  }

  /// Send one request and wait for the response carrying its id.
  ///
  /// The frame is written INSIDE the continuation body, after this request's
  /// id is in the pending table. Writing first and registering afterwards is a
  /// real race — measured under a loaded parallel run: the server answered
  /// while the caller was still hopping onto the actor, `consume` found no
  /// pending entry, dropped the line, and the request then sat until the 15
  /// second ceiling. `mcp-server.ts` registers before it writes for the same
  /// reason.
  @discardableResult
  func request(
    _ method: String,
    params: OracleJson = .object([:]),
  ) async throws -> JsonRpcResponse {
    let identifier = nextIdentifier
    nextIdentifier += 1
    let frame = OracleJson.object([
      "jsonrpc": .string("2.0"),
      "id": .number(Double(identifier)),
      "method": .string(method),
      "params": params,
    ])
    return try await withThrowingTaskGroup(of: JsonRpcResponse.self) { group in
      group.addTask {
        try await self.awaitResponse(identifier: identifier, sending: frame)
      }
      group.addTask {
        try await Task.sleep(for: .seconds(McpSession.requestTimeoutSeconds))
        let timedOut = OracleFailure.requestTimedOut(
          method: method,
          seconds: McpSession.requestTimeoutSeconds,
        )
        await self.fail(identifier: identifier, with: timedOut)
        throw timedOut
      }
      guard let first = try await group.next() else {
        throw OracleFailure.serverEnded(method: method)
      }
      group.cancelAll()
      return first
    }
  }

  /// A notification: no id, and nothing comes back.
  func notify(
    _ method: String,
    params: OracleJson = .object([:]),
  ) throws {
    try write(.object([
      "jsonrpc": .string("2.0"),
      "method": .string(method),
      "params": params,
    ]))
  }

  /// Write a raw line, for the framing cases that are not well-formed requests.
  func writeRaw(_ line: String) throws {
    guard let data = (line + "\n").data(using: .utf8) else {
      return
    }
    try input.write(contentsOf: data)
  }

  private func write(_ frame: OracleJson) throws {
    try writeRaw(frame.encoded)
  }

  private func awaitResponse(
    identifier: Int,
    sending frame: OracleJson,
  ) async throws -> JsonRpcResponse {
    if ended {
      throw OracleFailure.serverEnded(method: "request \(identifier)")
    }
    return try await withCheckedThrowingContinuation { continuation in
      pending[identifier] = continuation
      do {
        try writeRaw(frame.encoded)
      } catch {
        pending.removeValue(forKey: identifier)
        continuation.resume(throwing: error)
      }
    }
  }

  private func fail(
    identifier: Int,
    with error: Error,
  ) {
    pending.removeValue(forKey: identifier)?.resume(throwing: error)
  }

  /// The initialize handshake's advertised capabilities.
  func capabilities() async throws -> [String] {
    let response = try await request(
      "initialize",
      params: .object([
        "protocolVersion": .string("2024-11-05"),
        "capabilities": .object([:]),
        "clientInfo": .object([
          "name": .string("use-cases-blackbox"),
          "version": .string("0"),
        ]),
      ]),
    )
    let advertised = response.result?["capabilities"]?.objectValue ?? [:]
    return advertised.keys.sorted()
  }

  /// Call a tool and parse the CLI envelope out of its text content.
  func callTool(
    _ name: String,
    arguments: [String: OracleJson],
  ) async throws -> ToolOutcome {
    let raw = try await request(
      "tools/call",
      params: .object([
        "name": .string(name),
        "arguments": .object(arguments),
      ]),
    )
    let text = raw.result?.at("content.0.text")?.stringValue ?? ""
    return ToolOutcome(
      envelope: CliBinary.Envelope(json: (try? OracleJson.parse(text)) ?? .null),
      raw: raw,
    )
  }

  /// Close stdin and wait for the process to end, answering its exit code.
  ///
  /// Awaited, never polled: the exit arrives on the termination stream the
  /// session opened before the process was started.
  func closeInputAndWait() async -> Int32 {
    try? input.close()
    var status: Int32 = -1
    for await termination in terminations {
      status = termination
    }
    return status
  }

  func stop() {
    reader?.cancel()
    if process.isRunning {
      process.terminate()
    }
    try? input.close()
  }

  /// A session that goes out of scope takes its server with it, which is what
  /// the TypeScript suite's `afterAll(() => sessions.forEach(s => s.stop()))`
  /// does in one place. No test has to remember.
  deinit {
    if process.isRunning {
      process.terminate()
    }
  }
}

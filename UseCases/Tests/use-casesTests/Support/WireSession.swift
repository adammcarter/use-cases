import Foundation
import MCP

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

/// A host as an agent's host is to the server: it starts the program with pipes for its standard
/// streams and speaks JSON-RPC to it one line at a time. The program's output and its end arrive
/// as events; no wait here holds a thread.
actor WireSession {
  struct UnexpectedReply: Error {
    let reply: String
  }

  private let process: Process
  private let input: Pipe
  private let output: OutputReader
  private let lines: WireLines
  private let isReadingOnlyWhenAsked: Bool
  private let errors: Task<[UInt8], Never>
  private let end: ProcessEnd
  private var nextIdentifier = 0

  /// Starts `program` with `arguments`, in `folder`, with `environment` added to this process's.
  /// Its output is read at most `readSize` bytes a read: as it arrives, or, if
  /// `isReadingOnlyWhenAsked`, only while the test waits for a line it does not have yet, so that
  /// in between the pipe fills and the program's writes wait.
  init(
    program: URL,
    arguments: [String],
    folder: URL,
    environment: [String: String] = [:],
    readingBy readSize: Int = 65536,
    isReadingOnlyWhenAsked: Bool = false,
  ) throws {
    let process = Process()
    let input = Pipe()
    let outputPipe = Pipe()
    let errorPipe = Pipe()
    process.executableURL = program
    process.arguments = arguments
    process.currentDirectoryURL = folder
    process.standardInput = input
    process.standardOutput = outputPipe
    process.standardError = errorPipe

    process.environment = Self.environment(adding: environment)

    let output = OutputReader(
      outputPipe.fileHandleForReading,
      readSize: readSize,
      isPaused: isReadingOnlyWhenAsked,
    )
    let errorOutput = OutputReader(
      errorPipe.fileHandleForReading,
      readSize: 65536,
    )
    let lines = WireLines()

    // The only reader of the output, so its lines arrive in the order they were written.
    Task {
      for await chunk in output.chunks {
        await lines.receive(chunk)
      }

      await lines.finish()
    }

    self.process = process
    self.input = input
    self.output = output
    self.lines = lines
    self.isReadingOnlyWhenAsked = isReadingOnlyWhenAsked
    errors = Task {
      var bytes: [UInt8] = []

      for await chunk in errorOutput.chunks {
        bytes += chunk
      }

      return bytes
    }
    end = ProcessEnd(of: process)

    do {
      try process.run()
    } catch {
      try? output.stop()
      try? errorOutput.stop()

      throw error
    }
  }

  /// This process's environment with `added` over it; nil, which inherits it, when nothing is.
  private static func environment(adding added: [String: String]) -> [String: String]? {
    guard !added.isEmpty else {
      return nil
    }

    return ProcessInfo.processInfo.environment.merging(added) { _, added in
      added
    }
  }

  /// A program a failing test left running is ended with the session.
  deinit {
    if process.isRunning {
      kill(process.processIdentifier, SIGKILL)
    }
  }

  /// Sends a request and answers the reply that carries its identifier.
  func request(
    _ method: String,
    _ params: Value? = nil,
  ) async throws -> [String: Value] {
    nextIdentifier += 1
    let identifier = nextIdentifier
    var message: [String: Value] = [
      "jsonrpc": "2.0", "id": .int(identifier), "method": .string(method),
    ]
    message["params"] = params
    try send(message)

    guard
      let reply = await nextMessage(),
      reply["id"] == .int(identifier)
    else {
      throw UnexpectedReply(reply: "no reply to request \(identifier)")
    }

    return reply
  }

  func notify(
    _ method: String,
    _ params: Value? = nil,
  ) throws {
    var message: [String: Value] = ["jsonrpc": "2.0", "method": .string(method)]
    message["params"] = params
    try send(message)
  }

  /// The next line the program wrote to standard output, read as a JSON object; `nil` at the end
  /// of its output.
  func nextMessage() async -> [String: Value]? {
    guard let line = await nextLine() else {
      return nil
    }

    return try? JSONDecoder().decode([String: Value].self, from: line)
  }

  /// Sends a request and does not wait for the reply; answers its identifier.
  func start(
    _ method: String,
    _ params: Value? = nil,
  ) throws -> Int {
    nextIdentifier += 1
    var message: [String: Value] = [
      "jsonrpc": "2.0", "id": .int(nextIdentifier), "method": .string(method),
    ]
    message["params"] = params
    try send(message)

    return nextIdentifier
  }

  /// Sends bytes as they are, all in one write.
  func write(_ data: Data) throws {
    try input.fileHandleForWriting.write(contentsOf: data)
  }

  /// The next line the program wrote, as the bytes it wrote; `nil` at the end of its output.
  func nextLine() async -> Data? {
    guard isReadingOnlyWhenAsked else {
      return await lines.next()
    }

    if let line = await lines.takeReady() {
      return line
    }

    output.resume()
    let line = await lines.next()
    output.pause()

    return line
  }

  /// Returns once the program has written a line the test has not taken, or its output has
  /// ended; takes nothing. Not for a session that reads only when asked, which reads nothing here.
  func lineOrEnd() async {
    await lines.lineOrEnd()
  }

  /// Returns once the program's standard output has reached its end; takes nothing.
  func outputEnd() async {
    await lines.end()
  }

  /// The lines the program wrote that the test has not taken, once its output has ended.
  func remainingOutput() async -> [String] {
    var remaining: [String] = []

    while let line = await lines.next() {
      remaining.append(String(bytes: line, encoding: .utf8) ?? "")
    }

    return remaining
  }

  /// Returns once the program's standard output has reached its end, dropping whatever is left
  /// in it: the program has closed it, which it does by ending.
  func outputEnded() async {
    var line = await lines.next()

    while line != nil {
      line = await lines.next()
    }
  }

  /// The program's process identifier.
  var processIdentifier: Int32 {
    process.processIdentifier
  }

  /// Ends the program outright, giving it no chance to do anything.
  func killOutright() {
    kill(process.processIdentifier, SIGKILL)
  }

  /// Stops reading the program's output, as a host that has gone away does.
  func closeOutput() throws {
    try output.stop()
  }

  /// Whether the program ended by exiting, and not by a signal. Waits for it to end.
  func exitedNormally() async -> Bool {
    await end.termination().isExit
  }

  /// Closes the program's input, as a host does when it is done.
  func closeInput() throws {
    try input.fileHandleForWriting.close()
  }

  /// Waits for the program to end, and answers its exit code.
  func exitCode() async -> Int32 {
    await end.termination().status
  }

  /// Everything the program wrote to standard error, once it has reached its end.
  func standardError() async -> String {
    await String(
      bytes: errors.value,
      encoding: .utf8,
    ) ?? ""
  }

  private func send(_ message: [String: Value]) throws {
    let data = try JSONEncoder().encode(message)

    try input.fileHandleForWriting.write(contentsOf: data + Data("\n".utf8))
  }
}

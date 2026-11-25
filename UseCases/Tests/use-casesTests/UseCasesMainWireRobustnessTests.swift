import Foundation
import MCP
import Testing
import UseCasesTestSupport

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

/// The built `use-cases mcp` against a host that is slow, rude or gone: the frames stay whole,
/// the calls are stopped with the server, and the server never dies silently.
///
/// A test a call starts is held on a `ChildHold` and says on it that it is running; the wait for
/// that is raced against the program (`HoldRace`), so a program that answers or ends without
/// starting its test fails the test with what it said. The test learns that the server has ended
/// from the end of its standard output, checks what the server left behind, and only then
/// releases the hold and waits for the exit, so a server that left its test running fails the test
/// rather than waiting on it for ever.
struct UseCasesMainWireRobustnessTests {
  private func initialize(_ host: WireSession) async throws {
    _ = try await host.request(
      "initialize",
      [
        "protocolVersion": "2025-06-18",
        "capabilities": [:],
        "clientInfo": ["name": "wire", "version": "1"],
      ],
    )
    try await host.notify("notifications/initialized")
  }

  private func isAlive(_ pid: Int32) -> Bool {
    kill(pid, 0) == 0
  }

  @Test
  func `several big answers at once reach a slow reader as whole frames`() async throws {
    let workspace = try WireWorkspace.big(count: 400)
    defer {
      workspace.remove()
    }
    // The reader takes output only while the test asks for a line, a kilobyte a read: in
    // between, the pipe fills and the server's writes of frames far bigger than it wait.
    let host = try WireSession(
      program: BuiltProgram.url(),
      arguments: ["mcp"],
      folder: workspace.folder,
      readingBy: 1024,
      isReadingOnlyWhenAsked: true,
    )
    try await initialize(host)

    var identifiers: Set<Int> = []
    for _ in 0 ..< 6 {
      let identifier = try await host.start(
        "tools/call",
        [
          "name": "use_cases_search",
          "arguments": ["query": "lorem", "full": true, "page_size": 100],
        ],
      )
      identifiers.insert(identifier)
    }
    var answered: Set<Int> = []
    var smallest = Int.max

    for _ in identifiers {
      let line = try #require(await host.nextLine())
      let frame = try #require(
        try? JSONDecoder().decode([String: Value].self, from: line),
        "a frame that is not whole JSON: \(line.count) bytes",
      )
      let result = try #require(frame["result"]?.objectValue)
      #expect(result["isError"] == false)
      #expect(result["structuredContent"]?.objectValue?["command"] == "search")
      try answered.insert(#require(frame["id"]?.intValue))
      smallest = min(smallest, line.count)
    }

    #expect(answered == identifiers)
    #expect(smallest >= 150_000)
    try await host.closeInput()
    #expect(await host.exitCode() == 0)
  }

  @Test
  func `a call that arrives with the end of the input is not answered, and the server ends`(
  ) async throws {
    // Whether the call starts its run before the server sees the end of its input is the
    // server's schedule, not the test's: in every measured run it started nothing. A call that
    // has started is stopped and sealed as the cancelled-call tests below prove.
    let (workspace, hold) = try WireWorkspace.verifying { hold in
      "\(hold.shellText()); echo done >> done"
    }
    defer {
      hold.release()
      workspace.remove()
    }
    let host = try WireSession(
      program: BuiltProgram.url(),
      arguments: ["mcp"],
      folder: workspace.folder,
    )
    let messages: [[String: Value]] = [
      [
        "jsonrpc": "2.0", "id": 1, "method": "initialize",
        "params": [
          "protocolVersion": "2025-06-18", "capabilities": [:],
          "clientInfo": ["name": "burst", "version": "1"],
        ],
      ],
      ["jsonrpc": "2.0", "method": "notifications/initialized"],
      [
        "jsonrpc": "2.0", "id": 2, "method": "tools/call",
        "params": ["name": "use_cases_verify_tests", "arguments": ["step": "run"]],
      ],
    ]
    var burst = Data()
    for message in messages {
      try burst.append(JSONEncoder().encode(message))
      burst.append(UInt8(ascii: "\n"))
    }

    // Everything the host will ever say, in one write, and then its input is closed.
    try await host.write(burst)
    try await host.closeInput()

    var lines: [[String: Value]] = []
    while let message = await host.nextMessage() {
      lines.append(message)
    }
    #expect(
      lines.allSatisfy { $0["id"] != 2 },
      "a call that arrives with the end of the input is not answered",
    )

    hold.release()
    #expect(await host.exitCode() == 0)
  }

  // @use-case:mcp.server-lifetime#swift-tests.cancelled-call
  @Test
  func `a verify run whose lifeline ends stops its test and seals its run`() async throws {
    // The test holds the write end of the run's lifeline itself, as the run's input, and so can
    // wait for the run to end: this is where "sealed" is proven. That the real server hands its
    // commands a lifeline, and that its death ends it, is the killed-outright test below.
    let (workspace, hold) = try WireWorkspace.verifying { hold in
      "\(hold.shellText(announcing: "$PPID:$$")); echo done >> done"
    }
    defer {
      hold.release()
      workspace.remove()
    }
    let verifier = try WireSession(
      program: BuiltProgram.url(),
      arguments: ["verify", "--run"],
      folder: workspace.folder,
      environment: ["USE_CASES_LIFELINE_FD": "0"],
    )

    // The verify run is the parent of its test, which says so once it is held.
    let announced = try await HoldRace.waitUntilHeld(
      hold,
      beforeOutputEnds: verifier,
    )
    let pids = announced.split(separator: ":").compactMap { pid in
      Int32(pid)
    }
    try #require(pids.count == 2)
    #expect(await pids[0] == verifier.processIdentifier)
    try await verifier.closeInput()
    await verifier.outputEnded()

    let runs = workspace.runs()
    #expect(runs.count == 1)
    #expect(workspace.unsealedRuns().isEmpty, "the run was left open")
    #expect(!isAlive(pids[1]), "the test of the run is still running")

    hold.release()
    #expect(await verifier.exitedNormally())
  }

  // @use-case:end mcp.server-lifetime#swift-tests.cancelled-call

  @Test
  func `a server killed outright stops the test of the verify run it started`() async throws {
    // The run's test says on `stopped`, from its TERM trap, that it was told to stop, and ends.
    // The verify run is not the test's child: once its test has ended it seals its run and ends
    // by itself, which the test does not wait for ("sealed" is the lifeline test above).
    let stopped = try ChildSignal(
      at: FileManager.default.temporaryDirectory
        .appending(path: "use-cases-wire-stopped-\(UUID().uuidString)"),
    )
    defer {
      stopped.close()
    }
    let (workspace, hold) = try WireWorkspace.verifying { hold in
      "trap \"\(stopped.shellText(saying: "stopped")); exit 143\" TERM; "
        + "\(hold.shellText()); echo done >> done"
    }
    defer {
      hold.release()
      workspace.remove()
    }
    let host = try WireSession(
      program: BuiltProgram.url(),
      arguments: ["mcp"],
      folder: workspace.folder,
    )
    try await initialize(host)
    _ = try await host.start(
      "tools/call",
      ["name": "use_cases_verify_tests", "arguments": ["step": "run"]],
    )
    _ = try await HoldRace.waitUntilHeld(
      hold,
      beforeNextLineFrom: host,
    )

    await host.killOutright()

    #expect(try await stopped.next() == "stopped")
    hold.release()
    #expect(await !host.exitedNormally())
  }

  // @use-case:mcp.server-lifetime#swift-tests.cancelled-call
  @Test
  func `a call cancelled by the host stops a test that ignores the first signal, and seals its run`(
  ) async throws {
    let (workspace, hold) = try WireWorkspace.verifying { hold in
      "trap '' TERM; \(hold.shellText()); echo done >> done"
    }
    defer {
      hold.release()
      workspace.remove()
    }
    let host = try WireSession(
      program: BuiltProgram.url(),
      arguments: ["mcp"],
      folder: workspace.folder,
    )
    try await initialize(host)
    let call = try await host.start(
      "tools/call",
      ["name": "use_cases_verify_tests", "arguments": ["step": "run"]],
    )
    let held = try await #require(
      Int32(
        HoldRace.waitUntilHeld(
          hold,
          beforeNextLineFrom: host,
        ),
      ),
    )

    try await host.notify("notifications/cancelled", ["requestId": .int(call)])
    try await host.closeInput()

    var answers: [[String: Value]] = []
    while let message = await host.nextMessage() {
      answers.append(message)
    }
    #expect(
      answers.isEmpty,
      "the server writes nothing more once the host has cancelled the call and closed its input",
    )
    let runs = workspace.runs()
    #expect(runs.count == 1)
    #expect(workspace.unsealedRuns().isEmpty, "the run was killed before it could be sealed")
    #expect(!isAlive(held), "the test of the call is still running")

    hold.release()
    #expect(await host.exitCode() == 0)
  }

  // @use-case:end mcp.server-lifetime#swift-tests.cancelled-call

  // @use-case:mcp.server-lifetime#swift-tests.host-gone
  @Test
  func `closing the input stops the call running, and the server ends once its run is sealed`(
  ) async throws {
    let (workspace, hold) = try WireWorkspace.verifying { hold in
      "trap '' TERM; \(hold.shellText()); echo done >> done"
    }
    defer {
      hold.release()
      workspace.remove()
    }
    let host = try WireSession(
      program: BuiltProgram.url(),
      arguments: ["mcp"],
      folder: workspace.folder,
    )
    try await initialize(host)
    _ = try await host.start(
      "tools/call",
      ["name": "use_cases_verify_tests", "arguments": ["step": "run"]],
    )
    let held = try await #require(
      Int32(
        HoldRace.waitUntilHeld(
          hold,
          beforeNextLineFrom: host,
        ),
      ),
    )

    try await host.closeInput()

    // The test ignores the first signal, so sealing takes the core's grace: the server is still
    // there until it is done.
    await host.outputEnded()
    #expect(workspace.runs().count == 1)
    #expect(workspace.unsealedRuns().isEmpty, "the server ended before the run was sealed")
    #expect(!isAlive(held), "the test of the call is still running")

    hold.release()
    #expect(await host.exitCode() == 0)
  }

  // @use-case:end mcp.server-lifetime#swift-tests.host-gone

  // @use-case:mcp.server-lifetime#swift-tests.host-gone
  @Test
  func `a host that has gone away does not kill the server with a signal, which ends by itself`(
  ) async throws {
    let workspace = try WireWorkspace(files: ["use-cases.yml": "schema_version: 1\nroot: true\n"])
    defer {
      workspace.remove()
    }
    let host = try WireSession(
      program: BuiltProgram.url(),
      arguments: ["mcp"],
      folder: workspace.folder,
    )

    try await host.closeOutput()
    _ = try await host.start(
      "initialize",
      [
        "protocolVersion": "2025-06-18",
        "capabilities": [:],
        "clientInfo": ["name": "gone", "version": "1"],
      ],
    )

    #expect(await host.exitedNormally())
    #expect(await host.exitCode() == 0)
  }

  // @use-case:end mcp.server-lifetime#swift-tests.host-gone

  @Test
  func `a workspace that is no folder is refused before the server starts`(
  ) async throws {
    let workspace = try WireWorkspace(files: [:])
    defer {
      workspace.remove()
    }
    let host = try WireSession(
      program: BuiltProgram.url(),
      arguments: ["mcp", "--workspace", workspace.folder.appending(path: "missing").path],
      folder: workspace.folder,
    )

    #expect(await host.exitCode() == 2)
    #expect(await host.nextMessage() == nil)
    let message = await host.standardError()
    #expect(message.hasPrefix("error: '"))
    #expect(message.contains("missing' has no use-cases.yml"))
  }
}

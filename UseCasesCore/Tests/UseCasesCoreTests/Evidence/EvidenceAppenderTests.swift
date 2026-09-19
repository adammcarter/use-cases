import Foundation
import Testing
import TestSupport
@testable import UseCasesCore

/// Appending and voiding through the real append path, against what the
/// TypeScript returned and wrote with the same clock and random bytes: the
/// result, the thrown error, every file left behind byte for byte, and whether
/// the lock directory survived.
struct EvidenceAppenderTests {
  @Test(arguments: EvidenceGoldenCorpus.appendCaseNames)
  func `an append sequence writes and returns exactly what the TypeScript did`(
    caseName: String,
  ) async throws {
    let testCase = try EvidenceFixtures.goldenCase(caseName, in: "append")
    let workspace = try UseCasesFixtures.Workspace(tree: testCase["tree"])
    let context = try workspace.context()
    let lockPath = workspace.absolute("evidence/.locks/append.lock")

    for step in try #require(testCase["steps"]?.arrayValue) {
      let outcome = try await run(step, context: context)
      if let thrown = step["throws"] {
        guard case let .failure(error) = outcome else {
          Issue.record("expected \(caseName) to throw \(EvidenceFixtures.wire(thrown))")
          continue
        }
        EvidenceFixtures.expectThrown(error, equals: thrown, in: workspace)
      } else {
        let result = try outcome.get()
        let expected = try #require(step["result"])
        #expect(
          EvidenceFixtures.wire(result.resultData())
            == workspace.detokenized(EvidenceFixtures.wire(expected["data"])),
        )
        #expect(result.ledgerPath == workspace
          .detokenized(expected["ledger_path"]?.stringValue ?? ""))
      }
      #expect(FileManager.default
        .fileExists(atPath: lockPath) == (step["lock_exists_after"] == .bool(true)))
    }

    workspace.restoreModes()
    let files = try UseCasesFixtures.listTree(workspace.path)
    let expectedFiles = try #require(testCase["files_after"]?.arrayValue)
    #expect(files.map(\.path) == expectedFiles.compactMap { $0["path"]?.stringValue })
    for (actual, expected) in zip(files, expectedFiles) {
      #expect(actual.text == expected["text"]?.stringValue, "bytes of \(actual.path)")
    }
  }

  private func run(
    _ step: JSONValue,
    context: ResolvedWorkspaceContext,
  ) async throws -> Result<EvidenceAppendResult, EvidenceEventError> {
    let milliseconds = try #require(step["milliseconds"]?.numberValue)
    let random = try EvidenceFixtures.FixedRandomSource(hexadecimal: EvidenceFixtures.string(
      step,
      "random_hex",
    ))
    let clock: any EvidenceClock = step["clock_step"] == nil
      ? EvidenceFixtures.FixedClock(milliseconds: milliseconds)
      : EvidenceFixtures.SteppedClock(milliseconds: milliseconds)
    let appender = EvidenceAppender(clock: clock, randomSource: random)
    let options = try #require(step["options"])
    if step["operation"] == .string("void") {
      let voidOptions = try EvidenceFixtures.voidOptions(options, context: context)
      do throws(EvidenceEventError) {
        return try await .success(appender.appendVoid(voidOptions))
      } catch {
        return .failure(error)
      }
    }
    let appendOptions = try EvidenceFixtures.appendOptions(options, context: context)
    do throws(EvidenceEventError) {
      return try await .success(appender.append(appendOptions))
    } catch {
      return .failure(error)
    }
  }
}

/// The append behaviours the brief names, each pinned on its own.
struct EvidenceAppendBehaviourTests {
  private static let target = EvidenceTarget(
    useCaseIdentifier: "fixture.row",
    scenarioIdentifier: nil,
    useCaseSemanticHash: "sha256:" + String(repeating: "a", count: 64),
  )

  private static func options(
    _ context: ResolvedWorkspaceContext,
    key: String,
    summary: String = "Observed it.",
  ) -> EvidenceAppendOptions {
    EvidenceAppendOptions(
      context: context,
      idempotencyKey: key,
      target: target,
      kind: "manual_observation",
      result: "pass",
      summary: summary,
      actorType: .agent,
      hostSurface: "codex.cli",
    )
  }

  private static func ledgerText(_ workspace: UseCasesFixtures.Workspace) throws -> String {
    try UseCasesFixtures.listTree(workspace.path)
      .filter { entry in
        entry.path.hasSuffix(".jsonl")
      }
      .compactMap(\.text)
      .joined()
  }

  @Test
  func `a secret in the summary never reaches the ledger file`() async throws {
    let workspace = try UseCasesFixtures.Workspace(tree: nil)
    let appender = EvidenceAppender(
      clock: EvidenceFixtures.FixedClock(milliseconds: 1_767_323_045_678),
      randomSource: EvidenceFixtures.FixedRandomSource(hexadecimal: "0123456789abcdef0123"),
    )

    let result = try await appender.append(Self.options(
      workspace.context(),
      key: "secret",
      summary: "Deployed with password=hunter2hunter2 and ghp_abcdefghijklmnopqrstuvwxyz.",
    ))

    let text = try Self.ledgerText(workspace)
    #expect(!text.contains("hunter2"))
    #expect(!text.contains("abcdefghijklmnopqrstuvwxyz"))
    #expect(text.contains("password=[redacted]"))
    #expect(result.event["payload"]?["summary"]?.stringValue?.contains("hunter2") == false)
  }

  @Test
  func `only the first 18 of the 20 random hex digits reach the event id`() async throws {
    let first = try await appendedIdentifier(randomHex: "0123456789abcdef0123")
    let second = try await appendedIdentifier(randomHex: "0123456789abcdef01ff")
    let third = try await appendedIdentifier(randomHex: "0123456789abcdef02ff")

    #expect(first == "019b7ca9-8f2e-7012-8345-6789abcdef01")
    #expect(second == first)
    #expect(third != first)
  }

  private func appendedIdentifier(randomHex: String) async throws -> String {
    let workspace = try UseCasesFixtures.Workspace(tree: nil)
    let appender = EvidenceAppender(
      clock: EvidenceFixtures.FixedClock(milliseconds: 1_767_323_045_678),
      randomSource: EvidenceFixtures.FixedRandomSource(hexadecimal: randomHex),
    )
    return try await appender.append(Self.options(workspace.context(), key: "id")).event
      .eventIdentifier
  }

  @Test
  func `a held lock times out once the clock passes the deadline, polling every 25ms`(
  ) async throws {
    let workspace = try UseCasesFixtures.Workspace(tree: nil)
    try FileManager.default.createDirectory(
      atPath: workspace.absolute("evidence/.locks/append.lock"),
      withIntermediateDirectories: true,
    )
    let clock = EvidenceFixtures.SteppedClock(milliseconds: 1000)
    let appender = EvidenceAppender(
      clock: clock,
      randomSource: EvidenceFixtures.FixedRandomSource(hexadecimal: "0123456789abcdef0123"),
    )

    await #expect(throws: EvidenceEventError.lockTimeout) {
      try await appender.append(Self.options(workspace.context(), key: "held"))
    }

    // The deadline is `now + 30000` and the check is `now > deadline`, so the
    // wait that lands exactly ON the deadline still polls once more.
    #expect(await clock.sleeps == 1201)
    #expect(await clock.milliseconds == 1000 + 1201 * 25)
    #expect(FileManager.default
      .fileExists(atPath: workspace.absolute("evidence/.locks/append.lock")))
  }

  @Test
  func `the lock is released when the work under it throws`() async throws {
    let testCase = try EvidenceFixtures.goldenCase("damaged_history_refuses_append", in: "append")
    let workspace = try UseCasesFixtures.Workspace(tree: testCase["tree"])
    let appender = EvidenceAppender(
      clock: EvidenceFixtures.FixedClock(milliseconds: 0),
      randomSource: EvidenceFixtures.FixedRandomSource(hexadecimal: "0123456789abcdef0123"),
    )

    await #expect(throws: EvidenceEventError.ledgerDamaged) {
      try await appender.append(Self.options(workspace.context(), key: "damaged"))
    }
    #expect(!FileManager.default
      .fileExists(atPath: workspace.absolute("evidence/.locks/append.lock")))
    #expect(FileManager.default.fileExists(atPath: workspace.absolute("evidence/.locks")))
  }

  /// `rmSync(lockDir, { recursive: true, force: true })`: whatever was put
  /// inside the lock directory while it was held goes with it. The random
  /// source is drawn from under the lock, so it is where the file is dropped.
  @Test
  func `a lock directory holding files is still removed`() async throws {
    let workspace = try UseCasesFixtures.Workspace(tree: nil)
    let lockPath = workspace.absolute("evidence/.locks/append.lock")
    let appender = EvidenceAppender(
      clock: EvidenceFixtures.FixedClock(milliseconds: 0),
      randomSource: DroppingRandomSource(directory: lockPath),
    )

    _ = try await appender.append(Self.options(workspace.context(), key: "dropped"))

    #expect(!FileManager.default.fileExists(atPath: lockPath))
  }

  private struct DroppingRandomSource: EvidenceRandomSource {
    let directory: String

    func bytes(count: Int) -> [UInt8] {
      FileManager.default.createFile(atPath: directory + "/stray", contents: Data("x".utf8))
      _ = try? FileManager.default.createDirectory(
        atPath: directory + "/nested/deeper",
        withIntermediateDirectories: true,
      )
      FileManager.default.createFile(atPath: directory + "/nested/deeper/file", contents: Data())
      return [UInt8](repeating: 7, count: count)
    }
  }
}

/// ADR 0007 decision 10: concurrent writers never corrupt a ledger.
///
/// Every writer runs on its own Task with nothing in the process serialising
/// them: the appender is a plain struct, and the only thing between them is
/// the filesystem `mkdir` lock. ``StartSignal`` is an actor used purely as a
/// start line — each Task leaves it before it touches the filesystem — so the
/// writers reach the lock together instead of trickling in one by one.
///
/// This proves the guarantee between Tasks of one process. The situation the
/// lock exists for is separate `use-cases` processes; that version is row 4's.
struct EvidenceConcurrentWriterTests {
  private static let writers = 8
  private static let target = EvidenceTarget(
    useCaseIdentifier: "fixture.row",
    scenarioIdentifier: nil,
    useCaseSemanticHash: "sha256:" + String(repeating: "a", count: 64),
  )

  private static func record(
    _ context: ResolvedWorkspaceContext,
    key: String,
    summary: String,
  ) -> EvidenceAppendOptions {
    EvidenceAppendOptions(
      context: context,
      idempotencyKey: key,
      target: target,
      kind: "manual_observation",
      result: "pass",
      summary: summary,
      actorType: .agent,
      hostSurface: "codex.cli",
    )
  }

  /// The lock proof. Every writer voids the SAME evidence with the same
  /// expected head, so without mutual exclusion several see it active, all
  /// append sequence 2 to one file, and replay reports a sequence conflict.
  @Test
  func `concurrent voids of one evidence let exactly one through and leave a clean ledger`(
  ) async throws {
    let workspace = try UseCasesFixtures.Workspace(tree: nil)
    let context = try workspace.context()
    let seed = try await EvidenceAppender().append(Self.record(
      context,
      key: "seed",
      summary: "Seed.",
    ))

    let outcomes = await Self.voidConcurrently(seed.event.aggregateIdentifier, context: context)

    var appended: [EvidenceAppendResult] = []
    var failures: [EvidenceEventError] = []
    for outcome in outcomes {
      switch outcome {
      case let .success(result): appended.append(result)
      case let .failure(error): failures.append(error)
      }
    }
    #expect(appended.count == 1)
    #expect(appended.first?.isAppended == true)
    #expect(failures == Array(repeating: .invalidTransition, count: Self.writers - 1))

    let text = try String(contentsOfFile: seed.ledgerPath, encoding: .utf8)
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
    #expect(lines.count == 3 && lines.last == "")
    for line in lines.dropLast() {
      #expect((try? JSONParser.parse(String(line))) != nil, "line parses: \(line)")
    }
    let snapshot = try EvidenceReplay.replay(context: context)
    #expect(snapshot.isComplete)
    #expect(snapshot.aggregates.map(\.status) == [.voided])
    #expect(!FileManager.default
      .fileExists(atPath: workspace.absolute("evidence/.locks/append.lock")))
  }

  private static func voidConcurrently(
    _ evidence: String,
    context: ResolvedWorkspaceContext,
  ) async -> [Result<EvidenceAppendResult, EvidenceEventError>] {
    let start = StartSignal()
    return await withTaskGroup(of: Result<EvidenceAppendResult, EvidenceEventError>.self) { group in
      for writer in 0 ..< writers {
        group.addTask {
          await start.wait()
          do throws(EvidenceEventError) {
            return try await .success(EvidenceAppender().appendVoid(EvidenceVoidOptions(
              context: context,
              evidenceIdentifier: evidence,
              expectedHeadEventIdentifier: evidence,
              reason: "Writer \(writer).",
              idempotencyKey: "void-\(writer)",
              actorType: .agent,
              hostSurface: "codex.cli",
            )))
          } catch {
            return .failure(error)
          }
        }
      }
      await start.release(expecting: writers)
      var outcomes: [Result<EvidenceAppendResult, EvidenceEventError>] = []
      for await outcome in group {
        outcomes.append(outcome)
      }
      return outcomes
    }
  }

  /// No loss and no torn writes: 8 writers × 25 distinct events all land, each
  /// line whole, each event once.
  ///
  /// This test CANNOT detect a broken lock. Every recorded event is written to
  /// its own ledger file (`by-id/<prefix>/<event id>.jsonl`) in one `write`, so
  /// the writers never share a file; it passes with the lock removed. The lock
  /// is proved by the void race above.
  @Test
  func `eight concurrent writers lose, tear and duplicate no distinct event`() async throws {
    let workspace = try UseCasesFixtures.Workspace(tree: nil)
    let context = try workspace.context()
    let eventsPerWriter = 25

    let failures = await Self.appendConcurrently(eventsPerWriter, context: context)

    #expect(failures.isEmpty)
    var keys: [String] = []
    for ledger in try UseCasesFixtures.listTree(workspace.path)
      where ledger.path.hasSuffix(".jsonl")
    {
      let text = try #require(ledger.text)
      #expect(text.hasSuffix("\n"), "no torn tail in \(ledger.path)")
      for line in text.split(separator: "\n") {
        let event = try JSONParser.parse(String(line))
        try keys.append(#require(event["idempotency_key"]?.stringValue))
      }
    }
    let expectedKeys = (0 ..< Self.writers).flatMap { writer in
      (0 ..< eventsPerWriter).map { index in
        "writer-\(writer)-event-\(index)"
      }
    }
    #expect(keys.count == Self.writers * eventsPerWriter)
    #expect(Set(keys) == Set(expectedKeys))
    let snapshot = try EvidenceReplay.replay(context: context)
    #expect(snapshot.isComplete)
    #expect(snapshot.counts.eventsLoaded == Self.writers * eventsPerWriter)
    #expect(!FileManager.default
      .fileExists(atPath: workspace.absolute("evidence/.locks/append.lock")))
  }

  private static func appendConcurrently(
    _ eventsPerWriter: Int,
    context: ResolvedWorkspaceContext,
  ) async -> [EvidenceEventError] {
    let start = StartSignal()
    return await withTaskGroup(of: [EvidenceEventError].self) { group in
      for writer in 0 ..< writers {
        group.addTask {
          await start.wait()
          var failures: [EvidenceEventError] = []
          for index in 0 ..< eventsPerWriter {
            do throws(EvidenceEventError) {
              _ = try await EvidenceAppender().append(record(
                context,
                key: "writer-\(writer)-event-\(index)",
                summary: "Writer \(writer), event \(index).",
              ))
            } catch {
              failures.append(error)
            }
          }
          return failures
        }
      }
      await start.release(expecting: writers)
      var failures: [EvidenceEventError] = []
      for await batch in group {
        failures += batch
      }
      return failures
    }
  }
}

/// A start line for concurrent Tasks: each waits here, and all are released
/// together once every one has arrived. It guards no filesystem work.
actor StartSignal {
  private var waiting: [CheckedContinuation<Void, Never>] = []
  private var arrivals: [CheckedContinuation<Void, Never>] = []
  private var released = false

  func wait() async {
    guard !released else {
      return
    }
    await withCheckedContinuation { continuation in
      waiting.append(continuation)
      let ready = arrivals
      arrivals = []
      for arrival in ready {
        arrival.resume()
      }
    }
  }

  /// Returns once `count` Tasks are waiting, having released them all.
  func release(expecting count: Int) async {
    while waiting.count < count {
      await withCheckedContinuation { continuation in
        arrivals.append(continuation)
      }
    }
    released = true
    let ready = waiting
    waiting = []
    for continuation in ready {
      continuation.resume()
    }
  }
}

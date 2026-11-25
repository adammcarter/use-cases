import UseCasesTestSupport

/// Waits for a held test to announce itself, raced against the program that should start it: a
/// program that answers, or ends, before its test is held fails the wait with what it said,
/// rather than leaving the test waiting for a hold nobody will reach.
///
/// Each side waits in a task of its own, and the loser is left suspended, holding no thread: a
/// hold that was not announced is given up when the hold is let go of; a wait for the program's
/// output ends when its output does. Neither takes anything the test reads later.
enum HoldRace {
  /// The value `hold` announced, if it came before `session`'s program wrote a line or ended.
  static func waitUntilHeld(
    _ hold: ChildHold,
    beforeNextLineFrom session: WireSession,
  ) async throws -> String {
    let outcome = await race(hold) {
      await session.lineOrEnd()
    }

    switch outcome {
    case let .held(value?):
      return value
    case .held(nil):
      throw ProgramSpokeFirst(said: "nothing: the hold was given up")
    case .programSpoke:
      let line = await session.nextLine()
      let said = line.map { line in
        String(bytes: line, encoding: .utf8) ?? "\(line.count) bytes that are not UTF-8"
      }

      throw ProgramSpokeFirst(said: said ?? "nothing: its output ended")
    }
  }

  /// The value `hold` announced, if it came before `session`'s program's output ended.
  static func waitUntilHeld(
    _ hold: ChildHold,
    beforeOutputEnds session: WireSession,
  ) async throws -> String {
    let outcome = await race(hold) {
      await session.outputEnd()
    }

    switch outcome {
    case let .held(value?):
      return value
    case .held(nil):
      throw ProgramSpokeFirst(said: "nothing: the hold was given up")
    case .programSpoke:
      let output = await session.remainingOutput().joined(separator: "\n")
      let errors = await session.standardError()

      throw ProgramSpokeFirst(said: "its output ended: \(output) \(errors)")
    }
  }

  private static func race(
    _ hold: ChildHold,
    against program: @escaping @Sendable () async -> Void,
  ) async -> HoldRaceOutcome {
    let first = FirstToArrive<HoldRaceOutcome>()

    Task {
      await first.offer(.held(hold.waitUntilHeld()))
    }

    Task {
      await program()
      await first.offer(.programSpoke)
    }

    return await first.value()
  }
}

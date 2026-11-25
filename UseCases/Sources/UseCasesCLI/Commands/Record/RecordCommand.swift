import ArgumentParser
import Foundation
import UseCasesCore

/// `use-cases record` (chapter 16 §12): stores one verdict for one route, supplied by a person or
/// an agent, with the files that prove it when `--attach` names any. `--interactive` asks for
/// each value instead of taking it from the command line.
struct RecordCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: Self.name,
    abstract: "Record a verdict for a route: pass, fail, incomplete or error.",
  )

  static let name = "record"

  @OptionGroup
  var global: GlobalOptions

  // All three are optional here so that a missing one is told in the command's own words.
  @Argument(help: "The use case, or the start of its id.")
  var useCase: String?

  @Argument(help: "The route of that use case.")
  var route: String?

  @Argument(help: "pass, fail, incomplete or error.")
  var status: String?

  @Argument(help: "A note that goes with the verdict.")
  var message: String?

  @Flag(
    name: .long,
    help: "Ask for each value instead of taking it from the command line. Needs a terminal.",
  )
  var interactive = false

  @Option(
    name: .long,
    parsing: .upToNextOption,
    help: "Files to keep with the verdict as evidence.",
  )
  var attach: [String] = []

  /// What the command does from `workingDirectory`: refusals first, in the order a person fixes
  /// them, and then the run is written.
  ///
  /// - Parameters:
  ///   - loader: Reads the workspace and its links.
  ///   - session: What the command talks to: the recorder that checks the request and writes the
  ///     run, the person at the terminal, and the cancellation.
  ///   - workingDirectory: Where the command runs, which the files to attach are read from.
  func result(
    loader: any LinkedWorkspaceLoading,
    session: RecordSession,
    workingDirectory: URL,
  ) async -> CommandResult {
    let recorder = session.recorder

    if let refusal = upFrontRefusal(isTerminal: session.isTerminal) {
      return refusal
    }

    let linked: LinkedWorkspace

    do {
      linked = try await loader.load(
        from: global.start(from: workingDirectory),
      )
    } catch {
      return .refusal(
        error,
        command: Self.name,
        json: global.json,
      )
    }

    let request: RecordRequest

    do {
      request = try await self.request(
        in: linked,
        recorder: recorder,
        prompter: session.prompter,
        workingDirectory: workingDirectory,
      )
    } catch {
      return refusal(error)
    }

    return await record(
      request,
      in: linked,
      recorder: recorder,
      cancellation: session.cancellation,
    )
  }

  /// The command line is wrong before the workspace is looked at.
  private func upFrontRefusal(isTerminal: Bool) -> CommandResult? {
    if interactive {
      guard isTerminal, !global.json else {
        return refusal("record --interactive needs a terminal; give <use case> <route> <status>")
      }
      guard hasValues else {
        return nil
      }

      return refusal("record --interactive asks for every value; give none of them as arguments")
    }

    let missing = missingValues

    return missing.isEmpty ? nil : missingRefusal(missing)
  }

  private var hasValues: Bool {
    useCase != nil || route != nil || status != nil || message != nil
  }

  /// The values the command line did not give, by the names the refusal uses.
  private var missingValues: [String] {
    [
      ("use case", useCase),
      ("route", route),
      ("status", status),
    ].compactMap { name, value in
      value == nil ? name : nil
    }
  }

  private func record(
    _ request: RecordRequest,
    in linked: LinkedWorkspace,
    recorder: any VerdictRecording,
    cancellation: any CancellationScoping,
  ) async -> CommandResult {
    let plan: RecordPlan

    do {
      plan = try recorder.plan(
        request,
        in: linked.workspace,
        links: linked.resolution,
      )
    } catch {
      return refusal(error)
    }

    // The signals are held for the write itself, which `record --interactive` takes over only
    // now: a prompt must still be stopped with Ctrl-C. A request cancelled by now writes nothing;
    // one cancelled after finishes the write (chapter 13 §15).
    await cancellation.begin()

    guard await cancellation.claimWrite() else {
      await cancellation.end()

      return .cancelled(
        command: Self.name,
        json: global.json,
      )
    }

    let run: RecordedRun

    do {
      run = try recorder.commit(plan)
    } catch {
      await cancellation.end()

      return refusal(error)
    }

    let late = await cancellation.isCancelled()
    await cancellation.end()

    return report(
      run,
      notes: late ? [CommandResult.tooLate("the verdict was recorded")] : [],
    )
  }

  private func report(
    _ run: RecordedRun,
    notes: [String],
  ) -> CommandResult {
    let report = RecordReport(
      run: run,
      notes: notes,
    )

    guard global.json else {
      return .done(report.humanText(hint: !global.quiet))
    }

    do {
      return try .done(report.jsonText())
    } catch {
      return .refusal(
        .refused,
        message: "the recorded run could not be written as JSON",
        command: Self.name,
        json: true,
      )
    }
  }

  func refusal(_ error: RecordingError) -> CommandResult {
    .refusal(
      error.refusalKind,
      message: error.message,
      command: Self.name,
      json: global.json,
    )
  }

  func refusal(_ message: String) -> CommandResult {
    .refusal(
      .usage,
      message: message,
      command: Self.name,
      json: global.json,
    )
  }

  /// Too few values: what is missing, and the hint line that offers to ask for each (chapter 16
  /// §12, §18). The hint is for people only, so a script's document and message have none.
  private func missingRefusal(_ missing: [String]) -> CommandResult {
    let result = refusal(
      "record needs <use case> <route> <status>; missing: \(missing.joined(separator: ", "))",
    )

    guard !global.json, !global.quiet else {
      return result
    }

    return result.addingHint(
      "use-cases record --interactive",
      reason: "to be asked for each",
    )
  }
}

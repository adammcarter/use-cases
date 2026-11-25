import Foundation
import UseCasesCore

/// Asks for the use case, the route, the result and the note of a verdict, one after the other
/// (chapter 16 §12).
///
/// An answer that cannot be taken is a refusal, never asked again: a script that is fed answers
/// has to be told what was wrong with them.
struct RecordInterview {
  private static let answerPrompt = "           > "
  private static let notePrompt = "Note?      (optional) > "
  private static let statuses = ["pass", "fail", "incomplete", "error"]

  private let prompter: any Prompting

  init(prompter: any Prompting) {
    self.prompter = prompter
  }

  /// Asks about the use cases offered.
  func conduct(offers: [RecordOffer]) async throws(RecordInterviewError) -> RecordAnswers {
    guard !offers.isEmpty else {
      throw .recording(.noReadyUseCase)
    }

    await prompter.show("Use case?  " + Self.numbered(offers.map(\.useCase)))
    let useCase = try await choose(from: offers)

    await prompter.show("Route?     " + Self.numbered(useCase.routes.map(\.route)))
    let route = try await choose(from: useCase)

    if !route.steps.isEmpty {
      await prompter.show("           Steps: " + Self.steps(route.steps))
    }

    await prompter.show("Result?    " + Self.statuses.joined(separator: " / "))
    let status = try await answer(Self.answerPrompt)
    guard Self.statuses.contains(status) else {
      throw .recording(.unknownStatus(status))
    }

    let note = try await answer(Self.notePrompt)

    return RecordAnswers(
      useCase: useCase.useCase,
      route: route.route,
      status: status,
      message: note.isEmpty ? nil : note,
    )
  }

  private func choose(from offers: [RecordOffer]) async throws(RecordInterviewError)
    -> RecordOffer
  {
    let text = try await answer(Self.answerPrompt)

    do {
      return try RecordOffer.choose(
        text,
        among: offers,
      )
    } catch {
      throw .recording(error)
    }
  }

  private func choose(from offer: RecordOffer) async throws(RecordInterviewError)
    -> RecordRouteOffer
  {
    let text = try await answer(Self.answerPrompt)

    do {
      return try offer.chooseRoute(text)
    } catch {
      throw .recording(error)
    }
  }

  private func answer(_ question: String) async throws(RecordInterviewError) -> String {
    guard let line = await prompter.ask(question) else {
      throw .inputEnded
    }

    return line.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func numbered(_ names: [String]) -> String {
    names.enumerated().map { offset, name in
      "\(offset + 1) \(name)"
    }.joined(separator: "   ")
  }

  private static func steps(_ steps: [String]) -> String {
    steps.enumerated().map { offset, step in
      "\(offset + 1). \(step)"
    }.joined(separator: "  ")
  }
}

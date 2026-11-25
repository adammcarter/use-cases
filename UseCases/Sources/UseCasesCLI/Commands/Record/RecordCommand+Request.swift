import Foundation
import UseCasesCore

extension RecordCommand {
  /// What to record: the values of the command line, or the answers of the person at the
  /// terminal. Every file to attach is checked before the first question is asked.
  func request(
    in linked: LinkedWorkspace,
    recorder: any VerdictRecording,
    prompter: any Prompting,
    workingDirectory: URL,
  ) async throws(RecordInterviewError) -> RecordRequest {
    let attachments = attachmentLocations(from: workingDirectory)

    guard interactive else {
      return RecordRequest(
        useCase: useCase ?? "",
        route: route ?? "",
        status: status ?? "",
        message: message,
        attachments: attachments,
      )
    }

    let answers = try await answers(
      in: linked,
      recorder: recorder,
      prompter: prompter,
      attachments: attachments,
    )

    return RecordRequest(
      useCase: answers.useCase,
      route: answers.route,
      status: answers.status,
      message: answers.message,
      attachments: attachments,
    )
  }

  /// A refusal that stopped the questions, as the command tells it.
  func refusal(_ error: RecordInterviewError) -> CommandResult {
    switch error {
    case .inputEnded:
      refusal("input ended before every value was given; give <use case> <route> <status>")
    case let .recording(error):
      refusal(error)
    }
  }

  private func answers(
    in linked: LinkedWorkspace,
    recorder: any VerdictRecording,
    prompter: any Prompting,
    attachments: [URL],
  ) async throws(RecordInterviewError) -> RecordAnswers {
    do {
      try recorder.checkAttachments(at: attachments)
    } catch {
      throw .recording(error)
    }

    return try await RecordInterview(prompter: prompter).conduct(
      offers: recorder.offers(in: linked.workspace),
    )
  }

  /// The files to attach, as places: a relative path is read from where the command runs. It is
  /// joined by hand, as `--workspace` is.
  private func attachmentLocations(from workingDirectory: URL) -> [URL] {
    attach.map { path in
      let location =
        path.hasPrefix("/")
          ? URL(fileURLWithPath: path)
          : workingDirectory.appendingPathComponent(path)

      return location.standardizedFileURL
    }
  }
}

import UseCasesCore

extension DocsCommand {
  /// What the command line asks for: the following page of a search, passed alone, the list when
  /// there are no words, or words to show a guide by or search the guides for.
  func request() throws(DocsCommandError) -> DocsRequest {
    if let next {
      guard words.isEmpty, !exact, pageSize == nil else {
        throw .nextNotAlone
      }

      return .continuing(token: next)
    }

    guard !words.isEmpty else {
      return .list
    }

    return .words(
      words.joined(separator: " "),
      isExact: exact,
      pageSize: pageSize,
    )
  }

  /// The answer to a request that was understood and made.
  func report(of answer: DocsAnswer) -> CommandResult {
    let report = DocsReport(answer)

    guard global.json else {
      return .done(report.humanText(hint: !global.quiet))
    }

    do {
      return try .done(report.jsonText())
    } catch {
      return .refusal(
        .refused,
        message: "the guides could not be written as JSON",
        command: Self.name,
        json: true,
      )
    }
  }
}

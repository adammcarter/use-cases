import UseCasesCore

extension SearchCommand {
  /// What the command line asks for: the following page of a search, passed alone, or a new
  /// search of words or of a whole use case.
  func request() throws(SearchCommandError) -> SearchRequest {
    if let next {
      guard !asksForNewSearch else {
        throw .nextNotAlone
      }

      return .continuing(token: next)
    }

    let subject: SearchSubject

    switch (words.isEmpty, like) {
    case let (true, path?):
      subject = .like(path)
    case (false, nil):
      subject = .words(words.joined(separator: " "))
    case (true, nil):
      throw .needsWords
    case (false, _?):
      throw .wordsAndLike
    }

    return .new(
      SearchOptions(
        subject: subject,
        under: under,
        group: group,
        tiers: tier,
        states: state,
        fields: fields,
        isExact: exact,
        wantsFull: full,
        pageSize: pageSize,
      ),
    )
  }

  func usage(_ message: String) -> CommandResult {
    .refusal(
      .usage,
      message: message,
      command: Self.name,
      json: global.json,
    )
  }

  func refusal(_ error: UseCaseSearchError) -> CommandResult {
    .refusal(
      error.refusalKind,
      message: error.message,
      command: Self.name,
      json: global.json,
    )
  }

  /// The answer to a search that was understood and made.
  func report(of page: SearchPage) -> CommandResult {
    let report = SearchReport(page)

    guard global.json else {
      return .done(report.humanText(hint: !global.quiet))
    }

    do {
      return try .done(report.jsonText())
    } catch {
      return .refusal(
        .refused,
        message: "the matches could not be written as JSON",
        command: Self.name,
        json: true,
      )
    }
  }

  /// Whether anything but the token is given that only a new search takes.
  private var asksForNewSearch: Bool {
    !words.isEmpty || like != nil || under != nil || group != nil || tier != nil
      || state != nil || fields != nil || exact || full || pageSize != nil
  }
}

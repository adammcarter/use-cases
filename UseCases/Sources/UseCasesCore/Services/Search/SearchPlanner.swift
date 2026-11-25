import Foundation

/// Reads the flags of a search, the words typed, a `--like` use case and a `--next` token.
public struct SearchPlanner: SearchPlanning {
  private let reader: any AuthoredInputReading
  private let parser: any SearchQueryParsing
  private let codec: any SearchTokenCoding

  /// Makes the planner.
  ///
  /// - Parameter workingDirectory: Where a relative path given to `--like` is read from.
  public init(workingDirectory: URL) {
    self.init(
      reader: AuthoredInputReader(workingDirectory: workingDirectory),
      parser: SearchQueryParser(),
      codec: SearchTokenCodec(),
    )
  }

  init(
    reader: any AuthoredInputReading,
    parser: any SearchQueryParsing,
    codec: any SearchTokenCoding,
  ) {
    self.reader = reader
    self.parser = parser
    self.codec = codec
  }

  public func plan(_ request: SearchRequest) throws(UseCaseSearchError) -> SearchPlan {
    switch request {
    case let .new(options):
      try plan(new: options)
    case let .continuing(token):
      try plan(continuing: token)
    }
  }

  private func plan(new options: SearchOptions) throws(UseCaseSearchError) -> SearchPlan {
    let pageSize = try pageSize(options.pageSize)
    let fields = try fields(options.fields)
    let tiers = try Self.choices(
      options.tiers,
      as: ValueTier.self,
      refusing: UseCaseSearchError.unknownTiers,
    )
    let states = try Self.choices(
      options.states,
      as: VerificationStatus.self,
      refusing: UseCaseSearchError.unknownStates,
    )

    var excluded: String?
    let query: SearchQuery

    switch options.subject {
    case let .words(text):
      query = try parser.query(
        from: text,
        isExact: options.isExact,
      )
    case let .like(path):
      let like = try likeText(of: path)

      guard !like.words.isEmpty else {
        throw .likeHasNoText
      }

      excluded = like.identifier
      query = SearchQuery(
        words: like.words,
        phrases: [],
        exclusions: [],
        isExact: options.isExact,
      )
    }

    return SearchPlan(
      query: query,
      filters: SearchFilters(
        under: options.under,
        group: options.group,
        tiers: tiers,
        states: states,
        excluded: excluded,
      ),
      fields: fields,
      wantsFull: options.wantsFull,
      pageSize: pageSize,
      offset: 0,
      seal: nil,
    )
  }

  private func plan(continuing token: String) throws(UseCaseSearchError) -> SearchPlan {
    let plan: SearchPlan

    do {
      let value = try codec.parameters(in: token)
      plan = try SearchPlan(
        reading: AuthoredObject(
          value,
          at: "",
        ),
      )
    } catch {
      throw .invalidToken
    }

    // A token is read back only when it is exactly what a search writes, so an edit that changes
    // nothing a search reads is an edit all the same.
    guard
      let seal = plan.seal,
      codec.token(for: plan.document(sealedBy: seal)) == token,
      Self.pageSizes.contains(plan.pageSize),
      plan.offset >= 0
    else {
      throw .invalidToken
    }

    return plan
  }

  private static let pageSizes = PageWindow.sizes

  private func pageSize(_ text: String?) throws(UseCaseSearchError) -> Int {
    guard let text else {
      return PageWindow.defaultSize
    }

    guard let size = PageWindow.size(spelled: text) else {
      throw .pageSize(text)
    }

    return size
  }

  private func fields(_ text: String?) throws(UseCaseSearchError) -> [SearchField] {
    guard text != nil else {
      return SearchField.allCases
    }

    let chosen = try Self.choices(
      text,
      as: SearchField.self,
      refusing: UseCaseSearchError.unknownFields,
    )

    return SearchField.allCases.filter(chosen.contains)
  }

  /// The values of a comma separated flag; none for a flag that was not given.
  private static func choices<Choice: RawRepresentable & Hashable>(
    _ text: String?,
    as _: Choice.Type,
    refusing: ([String]) -> UseCaseSearchError,
  ) throws(UseCaseSearchError) -> Set<Choice> where Choice.RawValue == String {
    guard let text else {
      return []
    }

    var chosen: Set<Choice> = []
    var unknown: [String] = []

    for piece in text.split(separator: ",", omittingEmptySubsequences: false) {
      let word = piece.trimmingCharacters(in: .whitespaces)

      if let choice = Choice(rawValue: word) {
        chosen.insert(choice)
      } else {
        unknown.append(word)
      }
    }

    guard unknown.isEmpty else {
      throw refusing(unknown)
    }

    return chosen
  }

  private func likeText(of path: String) throws(UseCaseSearchError) -> LikeText {
    let input: AuthoredInput

    do {
      input = try reader.read(AuthoredInputSource(argument: path))
    } catch {
      throw .likeUnreadable(error.message)
    }

    guard case let .object(members) = input.value else {
      throw .likeUnreadable("\(input.name) is not a use case: it is not a mapping")
    }

    return LikeText(members)
  }
}

extension RecordOffer {
  /// The use case an answer names among the ones offered: its number in the list, its id, or the
  /// start of exactly one id. An exact id wins over a number, and a number over a start.
  ///
  /// - Parameters:
  ///   - answer: What was typed.
  ///   - offers: The use cases offered, in the order they were shown.
  public static func choose(
    _ answer: String,
    among offers: [RecordOffer],
  ) throws(RecordingError) -> RecordOffer {
    switch pick(
      answer,
      among: offers,
      by: \.useCase,
    ) {
    case let .found(offer):
      return offer
    case .none:
      throw .noUseCase(answer)
    case let .several(ids):
      throw .ambiguousUseCase(
        answer,
        matching: ids,
      )
    }
  }

  /// The route an answer names among the ones this use case offers, in the same ways.
  public func chooseRoute(_ answer: String) throws(RecordingError) -> RecordRouteOffer {
    switch Self.pick(
      answer,
      among: routes,
      by: \.route,
    ) {
    case let .found(route):
      return route
    case .none:
      throw .noRoute(
        useCase: useCase,
        route: answer,
      )
    case let .several(ids):
      throw .ambiguousRoute(
        useCase: useCase,
        route: answer,
        matching: ids,
      )
    }
  }

  private static func pick<Item>(
    _ answer: String,
    among items: [Item],
    by identifier: (Item) -> String,
  ) -> PrefixMatch<Item> {
    // An empty answer is the start of every id, which names none of them.
    guard !answer.isEmpty else {
      return .none
    }

    let isExactId = items.contains { item in
      identifier(item).isExactlyEqual(to: answer)
    }

    if !isExactId, let number = number(answer), items.indices.contains(number - 1) {
      return .found(items[number - 1])
    }

    return VerdictRecorder.match(
      answer,
      among: items,
      by: identifier,
    )
  }

  /// A whole number written with the digits 0 to 9 and nothing else.
  private static func number(_ answer: String) -> Int? {
    guard answer.utf8.allSatisfy({ $0 >= 0x30 && $0 <= 0x39 }) else {
      return nil
    }

    return Int(answer)
  }
}

/// A marker-style id: `<use-case-id>#[<route-id>.]<binding-id>`.
struct MarkerIdentifier: Equatable, Sendable {
  let useCase: String
  let route: String?
  let binding: String

  /// Reads `text`, nil when it is not spelled as a marker id.
  init?(_ text: String) {
    let halves = text.split(
      separator: "#",
      maxSplits: 1,
      omittingEmptySubsequences: false,
    )

    guard halves.count == 2 else {
      return nil
    }

    let useCase = String(halves[0])
    let rest = halves[1].split(
      separator: ".",
      omittingEmptySubsequences: false,
    ).map(String.init)

    guard
      useCase.split(
        separator: ".",
        omittingEmptySubsequences: false,
      ).allSatisfy(Self.isSegment),
      (1 ... 2).contains(rest.count),
      rest.allSatisfy(Self.isSegment)
    else {
      return nil
    }

    self.useCase = useCase
    route = rest.count == 2 ? rest[0] : nil
    binding = rest[rest.count - 1]
  }

  private static func isSegment(_ text: some StringProtocol) -> Bool {
    guard let first = text.first, let last = text.last else {
      return false
    }

    return first != "-" && last != "-" && text.allSatisfy { character in
      ("a" ... "z").contains(character) || ("0" ... "9").contains(character) || character == "-"
    }
  }
}

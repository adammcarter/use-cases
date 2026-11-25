extension ResolvedLink {
  /// Whether this link comes before another in the links document (chapter 16 §13): by use case
  /// id, then route (implementation links first), then binding id, then file by UTF-8 bytes, then
  /// start line as a number. The end line settles what is left.
  func precedes(_ other: ResolvedLink) -> Bool {
    if useCase != other.useCase {
      return useCase.precedesExactly(other.useCase)
    }

    if route != other.route {
      return precedesByRoute(other)
    }

    if binding != other.binding {
      return binding.precedesExactly(other.binding)
    }

    if path != other.path {
      return path < other.path
    }

    if startLine != other.startLine {
      return startLine < other.startLine
    }

    return endLine < other.endLine
  }

  private func precedesByRoute(_ other: ResolvedLink) -> Bool {
    switch (route, other.route) {
    case (nil, _?):
      true
    case let (mine?, theirs?):
      mine.precedesExactly(theirs)
    default:
      false
    }
  }
}

extension [ResolvedLink] {
  /// The links in the order of the links document (chapter 16 §13).
  var inLinkOrder: [ResolvedLink] {
    sorted { lhs, rhs in
      lhs.precedes(rhs)
    }
  }
}

import UseCasesCore

extension SearchReason {
  /// Where the text is, as a list shows it: `title`, `scenario main`, `out of scope`.
  var label: String {
    switch field {
    case .id, .title, .description, .intent:
      field.rawValue
    case .scenarios:
      named("scenario")
    case .outOfScope:
      "out of scope"
    case .validation:
      named("route")
    }
  }

  /// The label and the text in quotes, on one line.
  var listing: String {
    let line = text.split(
      whereSeparator: \.isWhitespace,
    ).joined(separator: " ")

    return "\(label): \"\(line)\""
  }

  private func named(_ kind: String) -> String {
    guard let location else {
      return kind
    }

    return kind + " " + location
  }
}

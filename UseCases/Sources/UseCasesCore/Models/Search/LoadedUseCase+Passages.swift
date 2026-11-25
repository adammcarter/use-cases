extension LoadedUseCase {
  /// The text of the use case in these fields, in the order a reader meets it.
  func passages(in fields: Set<SearchField>) -> [UseCasePassage] {
    var collected = CollectedPassages(fields: fields)

    collected.add(
      .id,
      identifier.text,
    )
    collected.add(
      .title,
      definition.title,
    )
    collected.add(
      .description,
      definition.description,
    )
    collected.add(
      .intent,
      definition.intent,
    )

    for scenario in definition.scenarios {
      let texts = [scenario.identifier.text] + scenario.given + scenario.when + scenario.then

      collected.add(
        .scenarios,
        texts,
        in: scenario.identifier.text,
      )
    }

    collected.add(
      .outOfScope,
      definition.outOfScope,
    )

    for route in definition.routes {
      let procedure = route.procedure
      let texts = [route.identifier.text] + (procedure?.setup ?? []) + (procedure?.steps ?? [])
        + (procedure?.reset ?? [])

      collected.add(
        .validation,
        texts,
        in: route.identifier.text,
      )
    }

    return collected.passages
  }
}

/// The passages of one use case, keeping only the fields searched.
private struct CollectedPassages {
  private let fields: Set<SearchField>
  private(set) var passages: [UseCasePassage] = []

  init(fields: Set<SearchField>) {
    self.fields = fields
  }

  mutating func add(
    _ field: SearchField,
    _ text: String?,
  ) {
    guard let text else {
      return
    }

    add(
      field,
      [text],
      in: nil,
    )
  }

  mutating func add(
    _ field: SearchField,
    _ texts: [String],
    in location: String? = nil,
  ) {
    guard fields.contains(field) else {
      return
    }

    for text in texts {
      passages.append(
        UseCasePassage(
          field: field,
          location: location,
          passage: SearchPassage(
            weight: field.weight,
            text: text,
          ),
        ),
      )
    }
  }
}

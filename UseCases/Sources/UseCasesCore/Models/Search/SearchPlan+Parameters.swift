extension SearchPlan {
  /// The version of the parameters a token carries.
  static let parametersVersion = 1

  /// Everything the plan says, as the JSON a token is made of.
  var parameters: StoreJSONValue {
    .present([
      "version": .integer(Self.parametersVersion),
      "words": .strings(query.words),
      "phrases": .array(query.phrases.map(StoreJSONValue.strings)),
      "exclusions": .array(query.exclusions.map(StoreJSONValue.strings)),
      "exact": .boolean(query.isExact),
      "fields": .strings(fields.map(\.rawValue)),
      "tiers": .strings(ValueTier.allCases.filter(filters.tiers.contains).map(\.rawValue)),
      "states": .strings(
        VerificationStatus.allCases.filter(filters.states.contains).map(\.rawValue),
      ),
      "under": filters.under.map(StoreJSONValue.string),
      "group": filters.group.map(StoreJSONValue.string),
      "excluded": filters.excluded.map(StoreJSONValue.string),
      "full": .boolean(wantsFull),
      "page_size": .integer(pageSize),
      "offset": .integer(offset),
    ])
  }

  /// The parameters with the seal that goes with them.
  func document(sealedBy seal: String) -> StoreJSONValue {
    guard case let .object(members) = parameters else {
      return parameters
    }

    return .object(
      members + [
        StoreJSONMember(
          key: "seal",
          value: .string(seal),
        ),
      ],
    )
  }

  /// The plan one page on.
  func moved(to offset: Int) -> SearchPlan {
    SearchPlan(
      query: query,
      filters: filters,
      fields: fields,
      wantsFull: wantsFull,
      pageSize: pageSize,
      offset: offset,
      seal: nil,
    )
  }

  /// Reads the parameters of a token, as `document(sealedBy:)` writes them.
  init(reading object: AuthoredObject) throws(AuthoredShapeError) {
    guard try object.requiredInteger("version") == Self.parametersVersion else {
      throw .wrongType(
        location: object.location(of: "version"),
        expected: "version \(Self.parametersVersion)",
      )
    }

    let tiers = try object.strings("tiers").map { text throws(AuthoredShapeError) in
      try Self.choice(
        text,
        as: ValueTier.self,
        at: object.location(of: "tiers"),
      )
    }
    let states = try object.strings("states").map { text throws(AuthoredShapeError) in
      try Self.choice(
        text,
        as: VerificationStatus.self,
        at: object.location(of: "states"),
      )
    }
    let fields = try object.strings("fields").map { text throws(AuthoredShapeError) in
      try Self.choice(
        text,
        as: SearchField.self,
        at: object.location(of: "fields"),
      )
    }

    try self.init(
      query: SearchQuery(reading: object),
      filters: SearchFilters(
        under: object.optionalString("under"),
        group: object.optionalString("group"),
        tiers: Set(tiers),
        states: Set(states),
        excluded: object.optionalString("excluded"),
      ),
      fields: fields,
      wantsFull: object.optionalBoolean("full") ?? false,
      pageSize: object.requiredInteger("page_size"),
      offset: object.requiredInteger("offset"),
      seal: object.requiredString("seal"),
    )
  }

  private static func choice<Choice: RawRepresentable>(
    _ text: String,
    as _: Choice.Type,
    at location: String,
  ) throws(AuthoredShapeError) -> Choice where Choice.RawValue == String {
    guard let choice = Choice(rawValue: text) else {
      throw .unknownChoice(
        location: location,
        text: text,
      )
    }

    return choice
  }
}

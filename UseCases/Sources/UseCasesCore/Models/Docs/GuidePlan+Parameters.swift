extension GuidePlan {
  /// The version of the parameters a token carries.
  static let parametersVersion = 1

  /// Names the command in a token's parameters, so a token of `search` is not one of `docs`.
  static let commandName = "docs"

  /// Everything the plan says, as the JSON a token is made of.
  var parameters: StoreJSONValue {
    .object(
      query.members + [
        StoreJSONMember(
          key: "command",
          value: .string(Self.commandName),
        ),
        StoreJSONMember(
          key: "version",
          value: .integer(Self.parametersVersion),
        ),
        StoreJSONMember(
          key: "page_size",
          value: .integer(pageSize),
        ),
        StoreJSONMember(
          key: "offset",
          value: .integer(offset),
        ),
      ],
    )
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
  func moved(to offset: Int) -> GuidePlan {
    GuidePlan(
      query: query,
      pageSize: pageSize,
      offset: offset,
      seal: nil,
    )
  }

  /// Reads the parameters of a token, as `document(sealedBy:)` writes them.
  init(reading object: AuthoredObject) throws(AuthoredShapeError) {
    guard try object.requiredString("command") == Self.commandName else {
      throw .wrongType(
        location: object.location(of: "command"),
        expected: "docs",
      )
    }

    guard try object.requiredInteger("version") == Self.parametersVersion else {
      throw .wrongType(
        location: object.location(of: "version"),
        expected: "version \(Self.parametersVersion)",
      )
    }

    try self.init(
      query: SearchQuery(reading: object),
      pageSize: object.requiredInteger("page_size"),
      offset: object.requiredInteger("offset"),
      seal: object.requiredString("seal"),
    )
  }
}

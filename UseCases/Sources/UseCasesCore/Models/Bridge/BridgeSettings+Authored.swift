extension BridgeSettings {
  /// Reads a file that passed the bridge schema.
  init(authored object: AuthoredObject) throws(AuthoredShapeError) {
    var links: [BridgeLinkTransformer] = []
    for entry in try object.objects("links") {
      try links.append(BridgeLinkTransformer(authored: entry))
    }

    var validations: [BridgeValidation] = []
    for entry in try object.objects("validations") {
      try validations.append(BridgeValidation(authored: entry))
    }

    self.init(
      links: links,
      validations: validations,
    )
  }
}

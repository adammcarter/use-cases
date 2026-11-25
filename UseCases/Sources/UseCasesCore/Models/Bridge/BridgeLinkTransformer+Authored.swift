extension BridgeLinkTransformer {
  init(authored object: AuthoredObject) throws(AuthoredShapeError) {
    try self.init(
      transformer: object.requiredTransformer("transformer"),
      settings: object.value(for: "settings"),
    )
  }
}

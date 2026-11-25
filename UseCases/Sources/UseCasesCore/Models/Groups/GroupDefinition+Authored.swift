extension GroupDefinition {
  /// Reads a group that passed the groups schema.
  init(
    name: String,
    authored object: AuthoredObject,
  ) throws(AuthoredShapeError) {
    do {
      self.name = try IdentifierSegment(validating: name)
    } catch {
      throw .invalidIdentifier(
        location: name,
        error,
      )
    }

    description = try object.optionalString("description")
    include = try object.optionalObject("include").map(GroupSelectors.init(authored:))
    exclude = try object.optionalObject("exclude").map(GroupSelectors.init(authored:))
  }
}

extension GroupsFile {
  /// Reads a file that passed the groups schema.
  init(authored object: AuthoredObject) throws(AuthoredShapeError) {
    let table = try object.requiredObject("groups")
    var groups: [GroupDefinition] = []

    for member in table.members {
      try groups.append(
        GroupDefinition(
          name: member.key,
          authored: AuthoredObject(
            member.value,
            at: table.location(of: member.key),
          ),
        ),
      )
    }

    self.groups = groups
  }
}

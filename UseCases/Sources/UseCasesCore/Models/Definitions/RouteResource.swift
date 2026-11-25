/// Repository material that changes a route's freshness but never expects a result
/// (chapter 06 "Resources").
enum RouteResource: Equatable, Sendable {
  /// One file, spelled as it is on disk.
  case file(WorkspacePath)

  /// Every file a pattern matches.
  case glob(PathPattern)

  /// Reads one item of `resources`.
  init(authored object: AuthoredObject) throws(AuthoredShapeError) {
    let kind = try object.requiredString("kind")

    switch kind {
    case "file":
      self = try .file(object.requiredPath("path"))
    case "glob":
      self = try .glob(object.requiredPattern("pattern"))
    default:
      throw .unknownChoice(
        location: object.location(of: "kind"),
        text: kind,
      )
    }
  }
}

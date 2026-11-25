/// Where a manual binding points: a file, and optionally a range in it (chapter 08).
struct ManualLocator: Equatable, Sendable {
  /// The file, relative to the workspace root and spelled as it is on disk.
  let file: WorkspacePath

  /// The range; absent for a whole-file binding.
  let range: ManualRange?

  init(
    file: WorkspacePath,
    range: ManualRange?,
  ) {
    self.file = file
    self.range = range
  }

  /// Reads a binding's `locator` mapping; `start` and `end` come together or not at all.
  init(authored object: AuthoredObject) throws(AuthoredShapeError) {
    let file = try object.requiredPath("file")
    let start = try object.optionalPosition("start")
    let end = try object.optionalPosition("end")

    switch (start, end) {
    case let (start?, end?):
      self.init(
        file: file,
        range: ManualRange(
          start: start,
          end: end,
        ),
      )
    case (nil, nil):
      self.init(
        file: file,
        range: nil,
      )
    case (_?, nil):
      throw .missing(location: object.location(of: "end"))
    case (nil, _?):
      throw .missing(location: object.location(of: "start"))
    }
  }
}

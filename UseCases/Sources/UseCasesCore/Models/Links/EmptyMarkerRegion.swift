/// A marked region with no code in it, tied to the use case it marks (chapter 08 "The linked
/// region"). The warning is the load's own; this says whose it is.
struct EmptyMarkerRegion: Equatable, Sendable {
  /// The full id of the use case the region marks.
  let useCase: String

  /// The warning as the workspace reports it.
  let diagnostic: Diagnostic

  /// The place and what to do, as the use case's own warning says it.
  var text: String {
    let place =
      diagnostic.position.map { position in
        "\(diagnostic.file.text):\(position.line)"
      } ?? diagnostic.file.text

    return "\(place): its marked region is empty; if the code moved, move its markers with it"
  }
}

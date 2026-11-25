/// Plain-language steps a person or an agent performs to prove a route (chapter 06
/// "Procedure"). Who performs them is never written.
struct Procedure: Equatable, Sendable {
  let setup: [String]
  let steps: [String]
  let reset: [String]

  init(
    setup: [String],
    steps: [String],
    reset: [String],
  ) {
    self.setup = setup
    self.steps = steps
    self.reset = reset
  }

  /// Reads a route's `procedure` mapping.
  init(authored object: AuthoredObject) throws(AuthoredShapeError) {
    guard object.contains("steps") else {
      throw .missing(location: object.location(of: "steps"))
    }

    try self.init(
      setup: object.strings("setup"),
      steps: object.strings("steps"),
      reset: object.strings("reset"),
    )
  }
}

/// Where in an authored file a refusal points.
struct YAMLLocation: Equatable, Sendable {
  let file: String
  let line: Int
}

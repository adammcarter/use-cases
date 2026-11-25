/// A scenario, or one example row of an outline, as Cucumber compiled it.
struct CucumberPickle: Equatable, Sendable {
  let uri: String
  let name: String
  let line: Int
}

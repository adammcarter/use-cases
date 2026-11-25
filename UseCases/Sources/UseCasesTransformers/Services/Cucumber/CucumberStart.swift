/// One attempt at running a test case.
struct CucumberStart: Equatable, Sendable {
  let identifier: String
  let testCase: String
  let attempt: Int
}

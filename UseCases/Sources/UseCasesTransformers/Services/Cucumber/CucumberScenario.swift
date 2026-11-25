/// A scenario that ran, with the results of the steps of its last attempt.
struct CucumberScenario: Equatable, Sendable {
  let pickle: CucumberPickle
  let steps: [ResultStatus]

  /// The worst step; a scenario that ran no step shows nothing.
  var status: ResultStatus {
    ResultStatus.worst(of: steps) ?? .incomplete
  }
}

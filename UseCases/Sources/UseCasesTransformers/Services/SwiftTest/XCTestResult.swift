/// One XCTest case as `swift test` printed its result.
struct XCTestResult: Equatable, Sendable {
  /// The module the class is in, when the line names it: two modules may each have a `FooTests`.
  let moduleName: String?
  let className: String
  let name: String
  let status: ResultStatus

  /// The test's id: module, class and name, as printed.
  var identifier: String {
    [moduleName, className, name].compactMap { part in
      part
    }.joined(separator: ".")
  }
}

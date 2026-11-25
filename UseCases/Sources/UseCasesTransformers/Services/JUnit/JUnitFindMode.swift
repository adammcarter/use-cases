/// How a JUnit report is matched to source: tools disagree on where a test lives.
enum JUnitFindMode: String, Equatable, Sendable {
  /// The report gives file and line (pytest with `junit_family=xunit1`).
  case fileLine = "file-line"
  /// The report gives the file; the test's name appears in it as a string (`node --test`).
  case fileName = "file-name"
  /// The report gives a name only; a declaration is searched for (CTest, Surefire, Gradle).
  case pattern
}

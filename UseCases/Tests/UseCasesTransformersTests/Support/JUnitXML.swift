/// Builds JUnit XML for the tests.
enum JUnitXML {
  static func testCase(
    _ name: String = "test_a",
    file: String? = "tests/test_a.py",
    line: String? = "2",
    inside: String = "",
    classname: String = "t",
  ) -> String {
    var attributes = "classname=\"\(classname)\" name=\"\(name)\""

    if let file {
      attributes += " file=\"\(file)\""
    }

    if let line {
      attributes += " line=\"\(line)\""
    }

    return "<testcase \(attributes)>\(inside)</testcase>"
  }

  static func suite(_ cases: String...) -> String {
    "<?xml version=\"1.0\"?><testsuite name=\"s\">\(cases.joined())</testsuite>"
  }
}

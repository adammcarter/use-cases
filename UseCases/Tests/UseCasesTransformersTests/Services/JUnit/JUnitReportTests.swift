import Foundation
import Testing
@testable import UseCasesTransformers

struct JUnitReportTests {
  private func parse(_ xml: String) throws -> JUnitReport {
    try JUnitReport(
      data: Data(xml.utf8),
      path: "report.xml",
    )
  }

  @Test
  func `cases are read in document order from any depth`() throws {
    let report = try parse(
      """
      <?xml version="1.0"?>
      <testsuites>
        <testsuite name="outer">
          <testcase classname="a.B" name="one" file="x.py" line="3"/>
          <testsuite name="inner">
            <testcase classname="a.C" name="two"><failure message="no"/></testcase>
          </testsuite>
        </testsuite>
      </testsuites>
      """,
    )

    #expect(report.cases.map(\.name) == ["one", "two"])
    #expect(report.cases[0].file == "x.py")
    #expect(report.cases[0].line == "3")
    #expect(report.cases[1].children == ["failure"])
  }

  @Test
  func `only elements directly inside a test case count as its children`() throws {
    let report = try parse(
      """
      <testsuite><testcase classname="a" name="n">
        <system-out><failure/></system-out>
        <skipped/>
      </testcase></testsuite>
      """,
    )

    #expect(report.cases[0].children == ["system-out", "skipped"])
  }

  @Test
  func `missing attributes read as empty`() throws {
    let report = try parse("<testsuite><testcase/></testsuite>")

    #expect(report.cases[0].className == "")
    #expect(report.cases[0].name == "")
    #expect(report.cases[0].file == nil)
  }

  @Test
  func `escaped text in attributes is unescaped`() throws {
    let report =
      try parse(
        #"<testsuite><testcase classname="a" name="x &lt; y &amp; &quot;z&quot;"/></testsuite>"#,
      )

    #expect(report.cases[0].name == #"x < y & "z""#)
  }

  @Test(arguments: ["", "not xml", "<testsuite><testcase></testsuite>", "<a><b></a>", "<a"])
  func `XML that is broken is refused, never guessed at`(xml: String) {
    #expect(throws: TransformerFailure.self) {
      try parse(xml)
    }
  }
}

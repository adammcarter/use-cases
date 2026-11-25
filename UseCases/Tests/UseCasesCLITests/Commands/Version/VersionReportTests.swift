import Foundation
import Testing
import UseCasesCore
@testable import UseCasesCLI

struct VersionReportTests {
  private let version = ProductVersion(
    release: "9.8.7",
    contract: 1,
    store: 1,
  )

  @Test
  func `people see the release on one line`() {
    let report = VersionReport(version: version)

    #expect(report.humanText() == "use-cases 9.8.7")
  }

  @Test
  func `scripts get the version document of chapter 16`() throws {
    let report = VersionReport(version: version)

    let text = try report.jsonText()
    let data = try #require(text.data(using: .utf8))
    let document = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

    #expect(document["output_version"] as? Int == 1)
    #expect(document["command"] as? String == "version")
    #expect(document["version"] as? String == "9.8.7")
    #expect(document["contract"] as? Int == 1)
    #expect(document["store"] as? Int == 1)
    #expect(document.count == 5)
  }
}

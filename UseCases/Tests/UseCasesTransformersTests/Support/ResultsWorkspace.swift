@testable import UseCasesTransformers

/// A workspace on disk with a report in it, and the requests the core would send for it.
struct ResultsWorkspace {
  static let reportName = ".use-cases/runs/run/reports/tests/report"

  let folder: TemporaryFolder

  init() throws {
    folder = try TemporaryFolder()
  }

  var reportPath: String {
    folder.absolute(ResultsWorkspace.reportName)
  }

  func writeReport(_ text: String) throws {
    try folder.write(
      ResultsWorkspace.reportName,
      text,
    )
  }

  /// The request for a report that is a folder: the files are written into it by the test.
  func writeReportFile(
    _ name: String,
    _ text: String,
  ) throws {
    try folder.write(
      ResultsWorkspace.reportName + "/" + name,
      text,
    )
  }

  func request(
    links: [RequestLink],
    settings: [String: JSONValue] = [:],
    exitCode: Int? = nil,
    workingDirectory: String = ".",
  ) -> ResultsRequest {
    ResultsRequest(
      links: links,
      output: ReportOutput(
        reportPath: reportPath,
        exitCode: exitCode,
        workingDirectory: workingDirectory,
      ),
      codeRoot: folder.path,
      settings: TransformerSettings(values: settings),
    )
  }
}

extension RequestLink {
  /// A validation link over the lines `start` to `end` of `file`.
  static func validation(
    _ file: String,
    _ start: Int,
    _ end: Int,
    binding: String = "check",
  ) -> RequestLink {
    RequestLink(
      key: "demo.a#unit-tests.\(binding)@\(file):\(start)",
      useCase: "demo.a",
      route: "unit-tests",
      binding: binding,
      role: .validation,
      file: file,
      range: LineRange(
        start: start,
        end: end,
      ),
    )
  }

  /// A validation link over a whole file.
  static func wholeFile(_ file: String) -> RequestLink {
    RequestLink(
      key: "demo.a#unit-tests.whole@\(file):1",
      useCase: "demo.a",
      route: "unit-tests",
      binding: "whole",
      role: .validation,
      file: file,
      range: nil,
    )
  }

  /// An implementation link, which results never go to.
  static func implementation(
    _ file: String,
    _ start: Int,
    _ end: Int,
  ) -> RequestLink {
    RequestLink(
      key: "demo.a#impl@\(file):\(start)",
      useCase: "demo.a",
      route: nil,
      binding: "impl",
      role: .implementation,
      file: file,
      range: LineRange(
        start: start,
        end: end,
      ),
    )
  }
}

extension ResultsResponse {
  /// The status given to the link with `key`, nil when it has no result.
  func status(of link: RequestLink) -> ResultStatus? {
    results.first { result in
      result.link == link.key
    }?.status
  }
}

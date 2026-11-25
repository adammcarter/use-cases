/// Where the tests wrote their report, and how the run command ended.
struct ReportOutput: Decodable, Equatable, Sendable {
  /// The report, a file or a folder. Read it; never change it.
  let reportPath: String
  /// The run command's exit code, or nil when the core does not know it.
  let exitCode: Int?
  /// The validation's working folder relative to the code root; "." is the project root.
  let workingDirectory: String

  /// The working folder as a prefix for workspace paths: "" for the project root.
  var folder: String {
    workingDirectory == "." ? "" : workingDirectory
  }

  init(
    reportPath: String,
    exitCode: Int?,
    workingDirectory: String = ".",
  ) {
    self.reportPath = reportPath
    self.exitCode = exitCode
    self.workingDirectory = workingDirectory
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)

    reportPath = try container.decode(
      String.self,
      forKey: .reportPath,
    )
    exitCode = try container.decodeIfPresent(
      Int.self,
      forKey: .exitCode,
    )
    workingDirectory = try container.decodeIfPresent(
      String.self,
      forKey: .workingDirectory,
    ) ?? "."
  }

  private enum CodingKeys: String, CodingKey {
    case reportPath = "report_path"
    case exitCode = "exit_code"
    case workingDirectory = "working_dir"
  }
}

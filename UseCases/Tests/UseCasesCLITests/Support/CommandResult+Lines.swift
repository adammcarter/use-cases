@testable import UseCasesCLI

extension CommandResult {
  /// The lines of stdout, blank lines kept and the newline that ends the last one not counted.
  var outputLines: [String] {
    guard !standardOutput.isEmpty else {
      return []
    }

    return String(standardOutput.dropLast()).components(separatedBy: "\n")
  }
}

import Foundation
@testable import UseCasesCore

/// Reads a tiny stand-in for `use-cases.yml`, one setting per line, so the discovery tests do
/// not need the real YAML reader:
///
///     root: true
///     use_cases_dir: specs
///     exclude: build/**, vendor
///     invalid
///
/// A line `invalid` makes the file unreadable as settings.
struct MockScopeSettingsReader: ScopeSettingsReading {
  func readSettings(
    fromText text: String,
    at path: WorkspacePath,
  ) throws(ScopeSettingsError) -> ScopeSettings {
    var isRoot = false
    var directory = "use-cases"
    var excludes: [String] = []

    for line in text.split(separator: "\n") {
      if line == "invalid" {
        throw ScopeSettingsError(
          problems: [
            ScopeSettingsProblem(
              position: try? SourcePosition(line: 1),
              code: "mock-invalid",
              message: "the settings are invalid",
            ),
          ],
        )
      }

      if line == "root: true" {
        isRoot = true
      } else if line.hasPrefix("use_cases_dir: ") {
        directory = String(line.dropFirst("use_cases_dir: ".count))
      } else if line.hasPrefix("exclude: ") {
        excludes = line.dropFirst("exclude: ".count).split(separator: ",").map { piece in
          piece.trimmingCharacters(in: .whitespaces)
        }
      }
    }

    return try settings(
      isRoot: isRoot,
      directory: directory,
      excludes: excludes,
    )
  }

  private func settings(
    isRoot: Bool,
    directory: String,
    excludes: [String],
  ) throws(ScopeSettingsError) -> ScopeSettings {
    do {
      return try ScopeSettings(
        isRoot: isRoot,
        useCasesDirectory: WorkspacePath(validating: directory),
        excludes: excludes.map { text in
          try PathPattern(validating: text)
        },
      )
    } catch {
      throw ScopeSettingsError(
        problems: [
          ScopeSettingsProblem(
            position: nil,
            code: "mock-invalid",
            message: "\(error)",
          ),
        ],
      )
    }
  }
}

import Foundation

struct BridgeSettingsLoader: BridgeSettingsLoading {
  /// The one name the file has.
  static let fileName = "use-cases-bridge.yml"

  private let fileSystem: any FileSystemReading
  private let yamlReader: any YAMLReading
  private let schema: any SchemaChecking
  private let checker: any BridgeSettingsChecking
  private let advisor: any BridgeSettingsAdvising
  private let locator: any OwnedFileLocating

  /// - Parameter schema: The checker for the bridge schema.
  init(
    fileSystem: any FileSystemReading,
    yamlReader: any YAMLReading,
    schema: any SchemaChecking,
    checker: any BridgeSettingsChecking,
    advisor: any BridgeSettingsAdvising,
    locator: any OwnedFileLocating,
  ) {
    self.fileSystem = fileSystem
    self.yamlReader = yamlReader
    self.schema = schema
    self.checker = checker
    self.advisor = advisor
    self.locator = locator
  }

  func load(
    in root: WorkspaceRoot,
    scopes: [LoadedScope],
  ) -> BridgeLoadResult {
    let file = WorkspacePath.root.appending(literal: Self.fileName)
    let location: OwnedFileLocation

    do {
      location = try locator.locate(
        Self.fileName,
        in: root,
        scopes: scopes,
        belowRoot: Diagnostic.bridgeBelowRoot,
      )
    } catch {
      return problems([.unreadableBridge(file, because: error)])
    }

    guard let entry = location.entry else {
      return problems(location.diagnostics)
    }

    guard entry.kind == .file else {
      return problems(location.diagnostics + [.bridgeNotAFile(file, kind: entry.kind)])
    }

    let text: String

    do {
      text = try fileSystem.readText(at: root.location(of: file))
    } catch {
      return problems(location.diagnostics + [.unreadableBridge(file, because: error)])
    }

    let read = read(
      text,
      file: file,
      in: root,
    )

    return BridgeLoadResult(
      settings: read.settings,
      diagnostics: location.diagnostics + read.diagnostics,
    )
  }

  private func read(
    _ text: String,
    file: WorkspacePath,
    in root: WorkspaceRoot,
  ) -> BridgeLoadResult {
    let value: AuthoredValue

    do {
      value = try yamlReader.read(
        text,
        file: file.text,
        kind: .settings,
      )
    } catch {
      return problems([error.diagnostic(in: file)])
    }

    let failures = schema.check(value)

    guard failures.isEmpty else {
      return problems(schemaProblems(
        failures,
        of: value,
        in: file,
      ))
    }

    let settings: BridgeSettings
    let writesValidations: Bool

    do {
      let object = try AuthoredObject(value, at: "")
      settings = try BridgeSettings(authored: object)
      writesValidations = object.contains("validations")
    } catch {
      return problems([Diagnostic(error: .invalidValue, in: file, message: error.description)])
    }

    let semantic = checker.check(
      settings,
      in: root,
      file: file,
    )

    guard semantic.isEmpty else {
      return problems(semantic)
    }

    return BridgeLoadResult(
      settings: settings,
      diagnostics: advisor.warnings(
        for: settings,
        writesValidations: writesValidations,
        in: file,
      ),
    )
  }

  private func problems(_ diagnostics: [Diagnostic]) -> BridgeLoadResult {
    BridgeLoadResult(
      settings: nil,
      diagnostics: diagnostics,
    )
  }

  /// What the schema found, sorted. A `report` that is a path is reported in its own words, and
  /// the schema's complaint about that same value is dropped: one problem is reported once.
  private func schemaProblems(
    _ failures: [SchemaFailure],
    of value: AuthoredValue,
    in file: WorkspacePath,
  ) -> [Diagnostic] {
    let paths = reportsThatArePaths(in: value)
    let covered = Set(paths.map { path in
      "validations/\(path.index)/report"
    })

    let others = failures.filter { failure in
      !covered.contains(failure.pathText)
    }.map { failure in
      failure.diagnostic(in: file)
    }

    let own = paths.map { path in
      Diagnostic.reportIsAPath(
        path.report,
        at: path.index,
        in: file,
      )
    }

    return (others + own).sorted()
  }

  /// The `report` of each validation that holds a slash or a backslash.
  private func reportsThatArePaths(in value: AuthoredValue) -> [(index: Int, report: String)] {
    guard
      case let .object(top) = value,
      case let .array(validations)? = top.first(where: { $0.key == "validations" })?.value
    else {
      return []
    }

    return validations.enumerated().compactMap { index, entry in
      guard
        case let .object(members) = entry,
        case let .string(report)? = members.first(where: { $0.key == "report" })?.value,
        report.unicodeScalars.contains(where: { $0 == "/" || $0 == "\\" })
      else {
        return nil
      }

      return (index, report)
    }
  }
}

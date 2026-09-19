import Foundation

/// Walks a fixture workspace and validates every file against the schema its
/// path belongs to — the engine behind `schema validate-fixtures`.
///
/// Which schema a file is validated against is decided by WHERE it sits, so the
/// folder layout is part of the contract: `use-cases/` holds use-case files,
/// `evidence/` holds event ledgers, and so on.
public enum FixtureWorkspaceValidator {
  /// What a walk of the workspace accumulates as it goes.
  private struct Scan {
    var diagnostics: [Diagnostic] = []
    var validatedIdentifiers = Set<String>()
    var useCaseFileForIdentifier: [String: String] = [:]
  }

  public static func validate(
    workspacePath: String,
    registry: SchemaRegistry,
  ) -> FixtureValidationResult {
    var scan = Scan()
    let workspace = URL(fileURLWithPath: workspacePath, isDirectory: true)
    let expectedState = readExpectedState(in: workspace)

    SyntheticContracts.validateCommonContracts(
      registry: registry,
      validatedIdentifiers: &scan.validatedIdentifiers,
      diagnostics: &scan.diagnostics,
    )

    for fileURL in listFiles(in: workspace) {
      validateFixtureFile(
        at: fileURL,
        relativePath: relativePath(of: fileURL, in: workspace),
        registry: registry,
        scan: &scan,
      )
    }

    let isComplete = !scan.diagnostics.contains { diagnostic in
      diagnostic.severity == .error
    }
    return FixtureValidationResult(
      isValid: isComplete,
      isComplete: isComplete,
      diagnostics: scan.diagnostics,
      validatedSchemaIdentifiers: SchemaRegistry.publicSchemaIdentifiers
        .filter(scan.validatedIdentifiers.contains),
      expectedState: expectedState,
    )
  }

  /// A file is validated against the schema its PATH belongs to; a file no
  /// folder claims is still parsed when it is YAML, so damage is still reported.
  private static func validateFixtureFile(
    at fileURL: URL,
    relativePath: String,
    registry: SchemaRegistry,
    scan: inout Scan,
  ) {
    guard relativePath != "expected.json" else {
      return
    }
    let schemaIdentifier = schemaIdentifier(forFixturePath: relativePath)
    let fileExtension = fileURL.pathExtension
    guard schemaIdentifier != nil || fileExtension == "yml" || fileExtension == "yaml" else {
      return
    }

    if fileExtension == "jsonl" {
      validateJSONLines(
        at: fileURL,
        relativePath: relativePath,
        schemaIdentifier: schemaIdentifier,
        registry: registry,
        scan: &scan,
      )
      return
    }

    let parsed = parseFixtureFile(at: fileURL, relativePath: relativePath)
    scan.diagnostics.append(contentsOf: parsed.diagnostics)
    guard parsed.isValid, let value = parsed.value, let schemaIdentifier else {
      return
    }

    let result = registry.validate(
      schemaIdentifier: schemaIdentifier,
      value: value,
      sourcePath: relativePath,
    )
    scan.validatedIdentifiers.insert(schemaIdentifier)
    scan.diagnostics.append(contentsOf: result.diagnostics)

    let useCaseFileSchema = SchemaRegistry
      .schemaIdentifier(forFileName: "use-case-file.schema.json")
    guard schemaIdentifier == useCaseFileSchema else {
      return
    }
    collectUseCaseIdentifiers(in: value, relativePath: relativePath, scan: &scan)
  }

  /// The schema a workspace-relative path is validated against, if any.
  static func schemaIdentifier(forFixturePath relativePath: String) -> String? {
    if relativePath == "use-cases.yml" {
      return SchemaRegistry.schemaIdentifier(forFileName: "workspace-config.schema.json")
    }
    if relativePath.hasPrefix("workflow-modes/")
      || relativePath.components(separatedBy: "/").last == "valid-sibling.yml"
    {
      return SchemaRegistry.schemaIdentifier(forFileName: "workflow-mode.schema.json")
    }
    if relativePath.hasPrefix("use-cases/") {
      return SchemaRegistry.schemaIdentifier(forFileName: "use-case-file.schema.json")
    }
    if relativePath.hasPrefix("evidence/") {
      return SchemaRegistry.schemaIdentifier(forFileName: "evidence-event.schema.json")
    }
    if relativePath.hasPrefix("demo-capsules/") {
      return SchemaRegistry.schemaIdentifier(forFileName: "demo-capsule.schema.json")
    }
    if relativePath.hasPrefix("presentation-plans/") {
      return SchemaRegistry.schemaIdentifier(forFileName: "presentation-plan.schema.json")
    }
    if relativePath.hasPrefix("showcase-runs/") {
      return SchemaRegistry.schemaIdentifier(forFileName: "showcase-event.schema.json")
    }
    return nil
  }

  // MARK: - Files

  private static func validateJSONLines(
    at fileURL: URL,
    relativePath: String,
    schemaIdentifier: String?,
    registry: SchemaRegistry,
    scan: inout Scan,
  ) {
    guard let schemaIdentifier,
          let contents = try? String(contentsOf: fileURL, encoding: .utf8)
    else {
      return
    }
    // Blank lines are dropped BEFORE numbering, so the number reported is the
    // position among events, not the position in the file.
    let lines = contents
      .components(separatedBy: "\n")
      .map { line in
        line.trimmingCharacters(in: .whitespaces)
      }
      .filter { line in
        !line.isEmpty
      }

    for (index, line) in lines.enumerated() {
      let sourcePath = "\(relativePath):\(index + 1)"
      do {
        let value = try JSONParser.parse(line)
        let result = registry.validate(
          schemaIdentifier: schemaIdentifier,
          value: value,
          sourcePath: sourcePath,
        )
        scan.validatedIdentifiers.insert(schemaIdentifier)
        scan.diagnostics.append(contentsOf: result.diagnostics)
      } catch {
        scan.diagnostics.append(
          Diagnostic(code: "parse_error", message: error.message, sourcePath: sourcePath),
        )
      }
    }
  }

  private static func parseFixtureFile(
    at fileURL: URL,
    relativePath: String,
  ) -> ParsedYamlResult {
    guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else {
      return ParsedYamlResult(
        isValid: false,
        value: nil,
        diagnostics: [
          Diagnostic(
            code: "parse_error",
            message: "unable to read \(relativePath)",
            sourcePath: relativePath,
          ),
        ],
      )
    }

    guard fileURL.pathExtension == "json" else {
      return YamlParser.parseToJSON(source: contents, sourcePath: relativePath)
    }

    do {
      return try ParsedYamlResult(
        isValid: true,
        value: JSONParser.parse(contents),
        diagnostics: [],
      )
    } catch {
      return ParsedYamlResult(
        isValid: false,
        value: nil,
        diagnostics: [
          Diagnostic(code: "parse_error", message: error.message, sourcePath: relativePath),
        ],
      )
    }
  }

  private static func readExpectedState(in workspace: URL) -> JSONValue? {
    let expectedURL = workspace.appendingPathComponent("expected.json")
    guard let contents = try? String(contentsOf: expectedURL, encoding: .utf8),
          let expected = try? JSONParser.parse(contents)
    else {
      return nil
    }
    return expected["expected_state"]
  }

  private static func collectUseCaseIdentifiers(
    in value: JSONValue,
    relativePath: String,
    scan: inout Scan,
  ) {
    guard value.isRecord, let rows = value["use_cases"]?.arrayValue else {
      return
    }
    for row in rows {
      guard row.isRecord, let identifier = row["id"]?.stringValue else {
        continue
      }
      guard let previousPath = scan.useCaseFileForIdentifier[identifier] else {
        scan.useCaseFileForIdentifier[identifier] = relativePath
        continue
      }
      scan.diagnostics.append(
        Diagnostic(
          code: "workspace.duplicate_use_case_id",
          message: "Use case '\(identifier)' appears in both \(previousPath) and "
            + "\(relativePath).",
          sourcePath: relativePath,
          entityIdentifier: identifier,
          relatedIdentifiers: [previousPath],
        ),
      )
    }
  }

  /// Every file under `root`, sorted by path, exactly as the TypeScript walks it.
  private static func listFiles(in root: URL) -> [URL] {
    let manager = FileManager.default
    guard manager.fileExists(atPath: root.path) else {
      return []
    }
    var files: [URL] = []
    var directories = [root]
    while let directory = directories.popLast() {
      let names = (try? manager.contentsOfDirectory(atPath: directory.path)) ?? []
      for name in names {
        let entry = directory.appendingPathComponent(name)
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: entry.path, isDirectory: &isDirectory) else {
          continue
        }
        if isDirectory.boolValue {
          directories.append(entry)
        } else {
          files.append(entry)
        }
      }
    }
    return files.sorted { $0.path < $1.path }
  }

  private static func relativePath(
    of fileURL: URL,
    in workspace: URL,
  ) -> String {
    let base = workspace.path.hasSuffix("/") ? workspace.path : workspace.path + "/"
    guard fileURL.path.hasPrefix(base) else {
      return fileURL.lastPathComponent
    }
    return String(fileURL.path.dropFirst(base.count))
  }
}

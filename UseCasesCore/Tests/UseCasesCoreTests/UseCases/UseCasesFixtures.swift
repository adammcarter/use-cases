import Foundation
import Testing
import TestSupport
@testable import UseCasesCore

/// Access to the generated TypeScript corpora, and the real directories the
/// matrix tests rebuild each case's tree in.
///
/// Expected results are compared as wire bytes through ``JSONWriter``: both
/// sides keep document order, so a value, a key or a key ORDER that differs
/// from what the TypeScript produced fails the comparison.
enum UseCasesFixtures {
  static let golden: Result<JSONValue, SchemaError> = parse(UseCasesGoldenCorpus.json)
  static let repositoryMatrix: Result<JSONValue, SchemaError> = parse(UseCasesRepositoryMatrixCorpus
    .json)

  /// Loaded once from the committed schema files, so a matrix failure is never
  /// an embedding failure.
  static let registry: Result<SchemaRegistry, SchemaError> = {
    do throws(SchemaError) {
      return try .success(SchemaRegistry(schemasDirectory: SchemaFixtures.schemasDirectory))
    } catch {
      return .failure(error)
    }
  }()

  private static func parse(_ text: String) -> Result<JSONValue, SchemaError> {
    do throws(SchemaError) {
      return try .success(JSONParser.parse(text))
    } catch {
      return .failure(error)
    }
  }

  /// The case called `name` in the golden corpus section `section`.
  static func goldenCase(
    _ name: String,
    in section: String,
  ) throws -> JSONValue {
    let cases = try #require(golden.get()[section]?.arrayValue, "corpus has no section \(section)")
    let match = cases.first { $0["name"]?.stringValue == name }
    return try #require(match, "corpus section \(section) has no case \(name)")
  }

  static func wire(_ value: JSONValue?) -> String {
    guard let value else {
      return "<absent>"
    }
    return JSONWriter.encode(value)
  }

  static func string(
    _ value: JSONValue,
    _ key: String,
  ) throws -> String {
    try #require(value[key]?.stringValue, "missing string \(key)")
  }

  // MARK: - Trees

  /// A case's tree, built for real under a fresh temporary directory: files
  /// (text or base64 bytes), directories, relative symlinks, FIFOs and
  /// permission changes, in corpus order.
  final class Workspace {
    let temporary: TemporaryDirectory
    private var restoredModes: [String] = []

    init(tree: JSONValue?) throws {
      temporary = try TemporaryDirectory()
      for entry in tree?.arrayValue ?? [] {
        try build(entry)
      }
    }

    deinit {
      for path in restoredModes.reversed() {
        chmod(path, 0o755)
      }
    }

    /// The workspace's REAL path, which is what node's `realpathSync` answers
    /// and what `<workspace>` in the corpus stands for.
    var path: String {
      WorkspaceFixture.realPath(temporary.url.path)
    }

    func absolute(_ relativePath: String) -> String {
      path + "/" + relativePath
    }

    /// Put `<workspace>` and `<pid>` back to what this run's are.
    func detokenized(_ text: String) -> String {
      text
        .replacingOccurrences(of: "<workspace>", with: path)
        .replacingOccurrences(of: ".tmp-<pid>", with: ".tmp-\(getpid())")
    }

    func context() throws -> ResolvedWorkspaceContext {
      try WorkspaceContextResolver.resolve(
        options: ResolveWorkspaceContextOptions(workspaceRoot: path),
        registry: registry.get(),
      )
    }

    /// Restore every changed permission now rather than at deinit, so the tree
    /// can be listed.
    func restoreModes() {
      for path in restoredModes.reversed() {
        chmod(path, 0o755)
      }
      restoredModes = []
    }

    private func build(_ entry: JSONValue) throws {
      let kind = try UseCasesFixtures.string(entry, "kind")
      let target = try absolute(UseCasesFixtures.string(entry, "path"))
      if kind != "mode" {
        try FileManager.default.createDirectory(
          atPath: (target as NSString).deletingLastPathComponent,
          withIntermediateDirectories: true,
        )
      }
      switch kind {
      case "file":
        let bytes: Data = if let base64 = entry["base64"]?.stringValue {
          try #require(Data(base64Encoded: base64))
        } else {
          try Data(UseCasesFixtures.string(entry, "text").utf8)
        }
        try bytes.write(to: URL(fileURLWithPath: target))
      case "directory":
        try FileManager.default.createDirectory(atPath: target, withIntermediateDirectories: true)
      case "symlink":
        try FileManager.default.createSymbolicLink(
          atPath: target,
          withDestinationPath: UseCasesFixtures.string(entry, "target"),
        )
      case "fifo":
        #expect(mkfifo(target, 0o644) == 0)
      case "mode":
        let mode = try #require(entry["mode"]?.numberValue)
        #expect(chmod(target, mode_t(mode)) == 0)
        restoredModes.append(target)
      default:
        Issue.record("unknown tree entry \(kind)")
      }
    }
  }

  /// Every path under `root`, directories suffixed `/`, in byte order — the
  /// generator's `listTree`.
  static func listTree(_ root: String) throws -> [(path: String, text: String?)] {
    var results: [(path: String, text: String?)] = []
    func walk(
      _ directory: String,
      _ prefix: String,
    ) throws {
      let names = try FileManager.default.contentsOfDirectory(atPath: directory)
      for name in names.sorted(by: JavaScriptStringOrder.codeUnitAscending) {
        let full = directory + "/" + name
        let relativePath = prefix + name
        let attributes = try FileManager.default.attributesOfItem(atPath: full)
        let type = attributes[.type] as? FileAttributeType
        if type == .typeDirectory {
          results.append((relativePath + "/", nil))
          try walk(full, relativePath + "/")
        } else if type == .typeSymbolicLink {
          results.append((relativePath, nil))
        } else {
          let data = try Data(contentsOf: URL(fileURLWithPath: full))
          results.append((relativePath, UTF8Text.decodeReplacingInvalid(Array(data))))
        }
      }
    }
    try walk(root, "")
    return results
  }

  // MARK: - Snapshot records

  /// The generator's `snapshotRecord`, built from a Swift snapshot so the two
  /// can be compared as wire JSON.
  static func record(
    _ snapshot: MatrixSnapshot,
    probes: JSONValue?,
  ) -> JSONObject {
    var record = JSONObject()
    record["complete"] = .bool(snapshot.isComplete)
    record["integrity"] = .object(JSONObject([
      ("state", .string(snapshot.integrity.state.rawValue)),
      ("populated", .bool(snapshot.integrity.isPopulated)),
      ("blockingDiagnosticCount", .number(Double(snapshot.integrity.blockingDiagnosticCount))),
    ]))
    record["validation"] = snapshot.validationResult()
    record["list"] = snapshot.listResult(for: snapshot.queryUseCases())
    record["diagnostics"] = .array(snapshot.diagnostics.map(\.jsonValue))
    record["candidates"] = .array(snapshot.candidates.map(candidate))
    record["addressable_ids"] = .array(snapshot.addressableUseCases.map { useCase in
      .string(useCase.identifier)
    })
    record["use_case_resolutions"] = .array((probes?["useCases"]?.arrayValue ?? [])
      .compactMap(\.stringValue).map { identifier in
        var entry = JSONObject([("id", .string(identifier))])
        let resolution = snapshot.resolveUseCase(identifier)
        entry["kind"] = .string(resolution.kind)
        entry["source_paths"] = .array(sourcePaths(resolution).map(JSONValue.string))
        return .object(entry)
      })
    record["scenario_resolutions"] = .array((probes?["scenarios"]?.arrayValue ?? []).map { pair in
      let items = pair.arrayValue ?? []
      let useCase = items.first?.stringValue ?? ""
      let scenario = items.last?.stringValue ?? ""
      let resolution = snapshot.resolveScenario(
        useCaseIdentifier: useCase,
        scenarioIdentifier: scenario,
      )
      let paths: [String] = switch resolution {
      case let .resolved(_, _, loaded): [loaded.source.path]
      case let .ambiguous(_, _, candidates): candidates.map(\.source.path)
      case .missing: []
      }
      return .object(JSONObject([
        ("use_case_id", .string(useCase)),
        ("scenario_id", .string(scenario)),
        ("kind", .string(resolution.kind)),
        ("source_paths", .array(paths.map(JSONValue.string))),
      ]))
    })
    return record
  }

  static func candidate(_ item: LoadedUseCase) -> JSONValue {
    .object(JSONObject([
      ("id", .string(item.identifier)),
      ("feature_id", item.feature["id"] ?? .null),
      ("semantic_hash", .string(item.semanticHash)),
      ("source_path", .string(item.source.path)),
      ("json_pointer", .string(item.source.jsonPointer)),
      ("file_byte_hash", .string(item.source.fileByteHash)),
    ]))
  }

  private static func sourcePaths(_ resolution: UseCaseResolution) -> [String] {
    switch resolution {
    case let .resolved(_, useCase): [useCase.source.path]
    case let .ambiguous(_, candidates): candidates.map(\.source.path)
    case .missing: []
    }
  }

  /// Compare every member of an expected record against the actual one,
  /// member by member so a failure names the part that differs.
  static func expectMembers(
    of expected: JSONValue?,
    equal actual: JSONObject,
    in workspace: Workspace,
    sourceLocation: SourceLocation = #_sourceLocation,
  ) throws {
    let expectedObject = try #require(expected?.objectValue, sourceLocation: sourceLocation)
    for member in expectedObject.pairs {
      let expectedText = workspace.detokenized(wire(maskingParserWording(member.value)))
      let actualText = wire(actual[member.key].map(maskingParserWording))
      #expect(actualText == expectedText, "member \(member.key)", sourceLocation: sourceLocation)
    }
  }

  /// A YAML syntax error's MESSAGE comes from the parser library — `yaml` in
  /// the TypeScript, Yams here — and is accepted as differing (see
  /// docs/rewrite/ladder-notes.md, row 4): only its `parse_error` code is
  /// contract. The fatal UTF-8 decoding message is this port's own and stays
  /// compared exactly.
  static func maskingParserWording(_ value: JSONValue) -> JSONValue {
    switch value {
    case let .array(items):
      return .array(items.map(maskingParserWording))
    case let .object(object):
      var masked = JSONObject()
      for member in object.pairs {
        masked[member.key] = maskingParserWording(member.value)
      }
      if masked["code"] == .string("parse_error"),
         masked["message"] != .string(UseCaseFileValidator.invalidEncodingMessage)
      {
        masked["message"] = .string("<YAML parser wording>")
      }
      return .object(masked)
    default:
      return value
    }
  }
}

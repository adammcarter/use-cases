import Foundation
import Testing
import TestSupport
@testable import UseCasesCore

/// The stable `UCM_*` registry, its generated reference page, and the map from
/// internal codes — each against the TypeScript registry, taken from the
/// oracle corpus rather than copied by hand.
struct PublicErrorRegistryTests {
  private static func registry() throws -> JSONValue {
    try #require(EvidenceFixtures.section("registry").objectValue.map(JSONValue.object))
  }

  @Test
  func `every entry matches the TypeScript registry, in declaration order`() throws {
    let expected = try #require(Self.registry()["entries"]?.arrayValue)

    #expect(PublicErrorRegistry.entries.count == 68)
    #expect(PublicErrorRegistry.entries.count == expected.count)
    for (entry, oracle) in zip(PublicErrorRegistry.entries, expected) {
      #expect(entry.code.rawValue == oracle["code"]?.stringValue)
      #expect(entry.message == oracle["message"]?.stringValue)
      #expect(entry.severity.rawValue == oracle["severity"]?.stringValue)
      #expect(entry.surface.rawValue == oracle["surface"]?.stringValue)
      #expect(entry.documentationPath == oracle["docs"]?.stringValue)
    }
    #expect(Set(PublicErrorRegistry.entries.map(\.code)) == Set(PublicErrorCode.allCases))
  }

  @Test
  func `codes are listed in the code unit order TypeScript's bare sort gives`() throws {
    let expected = try #require(Self.registry()["codes"]?.arrayValue).compactMap(\.stringValue)

    #expect(PublicErrorRegistry.codes.map(\.rawValue) == expected)
    #expect(PublicErrorRegistry.codes.map(\.rawValue).firstIndex(of: "UCM_INVALID_ID")
      .map {
        $0 < PublicErrorRegistry.codes.map(\.rawValue)
          .firstIndex(of: "UCM_LEDGER_CHAIN_BROKEN") ?? 0
      } == true)
  }

  @Test
  func `an entry is found by its code`() {
    #expect(PublicErrorRegistry.entry(for: .evidenceLockTimeout)?
      .message == "Timed out acquiring evidence append lock.")
    #expect(PublicErrorRegistry.entry(for: .pathEscape)?.surface == .path)
  }

  @Test
  func `the rendered page equals the committed docs/reference/error-codes.md byte for byte`(
  ) throws {
    let path = SchemaFixtures.repositoryRoot.appendingPathComponent("docs/reference/error-codes.md")
    let committed = try Data(contentsOf: path)

    #expect(Array(ErrorCodesDocument.render().utf8) == Array(committed))
  }

  @Test
  func `the rendered page equals the TypeScript renderer's output`() throws {
    let expected = try #require(Self.registry()["markdown"]?.stringValue)

    #expect(ErrorCodesDocument.render() == expected)
  }

  @Test
  func `a pipe in a message is escaped inside its table cell`() {
    #expect(ErrorCodesDocument.escapeCell("a|b||c") == #"a\|b\|\|c"#)
  }

  // MARK: - Internal codes

  private static func oracleEnumMap(_ family: String) throws -> [String: String] {
    let pairs = try #require(registry()["enum_maps"]?[family]?.arrayValue)
    return Dictionary(uniqueKeysWithValues: pairs.compactMap { pair in
      guard let key = pair.arrayValue?.first?.stringValue,
            let value = pair.arrayValue?.last?.stringValue
      else {
        return nil
      }
      return (key, value)
    })
  }

  private static func swiftEnumMap(_ family: String) -> [String: String] {
    func mapped<Code: RawRepresentable<String> & CaseIterable>(
      _ codes: Code.AllCases,
      _ publicCode: (Code) -> PublicErrorCode?,
    ) -> [String: String] {
      Dictionary(uniqueKeysWithValues: codes.compactMap { code in
        publicCode(code).map { mapped in
          (code.rawValue, mapped.rawValue)
        }
      })
    }
    switch family {
    case "marker": return mapped(MarkerErrorCode.allCases, PublicErrorCodeMap.publicCode(for:))
    case "registry": return mapped(RegistryErrorCode.allCases, PublicErrorCodeMap.publicCode(for:))
    case "evidence": return mapped(EvidenceErrorCode.allCases, PublicErrorCodeMap.publicCode(for:))
    case "swiftFunc": return mapped(
        SwiftFunctionErrorCode.allCases,
        PublicErrorCodeMap.publicCode(for:),
      )
    case "signature": return mapped(
        SignatureFailureCode.allCases,
        PublicErrorCodeMap.publicCode(for:),
      )
    default: return [:]
    }
  }

  @Test(arguments: ["marker", "registry", "evidence", "swiftFunc", "signature"])
  func `an internal enum family maps to the public codes TypeScript maps it to`(
    family: String,
  ) throws {
    let expected = try Self.oracleEnumMap(family)

    #expect(!expected.isEmpty)
    #expect(Self.swiftEnumMap(family) == expected)
  }

  @Test
  func `the string code map equals the TypeScript map entry for entry`() throws {
    let expected = try #require(Self.registry()["string_map"]?.arrayValue).map { pair in
      "\(pair.arrayValue?.first?.stringValue ?? "")=\(pair.arrayValue?.last?.stringValue ?? "")"
    }

    let actual = PublicErrorCodeMap.stringCodes.map { pair in
      "\(pair.code)=\(pair.publicCode.rawValue)"
    }
    #expect(actual.sorted() == expected.sorted())
    #expect(actual.count == 27)
    for pair in PublicErrorCodeMap.stringCodes {
      #expect(PublicErrorCodeMap.publicCode(forStringCode: pair.code) == pair.publicCode)
    }
    #expect(PublicErrorCodeMap.publicCode(forStringCode: "path.escap\u{65}\u{301}") == nil)
    #expect(PublicErrorCodeMap.publicCode(forStringCode: "unknown") == nil)
  }

  /// Codes a Swift error can raise that TypeScript ALSO leaves out of its
  /// registry. Adding a code to an enum below that is neither mapped nor listed
  /// here fails this test: parity with TypeScript, not completeness.
  static let knownUnmappedCodes: Set<String> = [
    // node's filesystem errors (`FileAccessError`): the TypeScript lets node's
    // error escape with its errno code, and maps none of them.
    "ENOENT", "EACCES", "EISDIR", "ENOTDIR", "EEXIST",
    // node's `TextDecoder` refusing invalid UTF-8: TypeScript passes it through.
    "ERR_ENCODING_INVALID_ENCODED_DATA",
    // A `TypeError` reading a malformed event, and canonical JSON refusing a
    // non-finite number: plain errors in TypeScript, with no code at all.
    "unreadable_event", "non_finite_number",
  ]

  /// Every case of the typed errors whose codes TypeScript raises as
  /// `UseCasesPluginError` string codes. They carry payloads, so they are not
  /// `CaseIterable`. `caseCount(_:)` switches over each with no `default`: a new
  /// case breaks the build there, and once its count is raised the test below
  /// fails until the case is sampled here.
  ///
  /// Deliberately excluded, because TypeScript maps none of their codes and
  /// adding registry entries would change the frozen contract (decision 8):
  /// `SchemaError`, `KeyringError`, `GitError`, `VerificationContextHashError`,
  /// `ProofSignatureError`, `CodeUnitCanonicalJSONError`, `YamlConversionError`,
  /// `UseCaseMatrixError`, `EvidenceLedgerError`.
  private static let evidenceSamples: [EvidenceEventError] = [
    .ledgerDamaged, .idempotencyConflict, .invalidTransition, .expectedHeadMismatch, .lockTimeout,
    .fileAccess(FileAccessError(errorNumber: ENOENT, operation: "open", path: "/x")),
    .fileAccess(FileAccessError(errorNumber: EACCES, operation: "open", path: "/x")),
    .fileAccess(FileAccessError(errorNumber: ENOTDIR, operation: "mkdir", path: "/x")),
    .fileAccess(FileAccessError(errorNumber: EISDIR, operation: "open", path: "/x")),
    .fileAccess(FileAccessError(errorNumber: EEXIST, operation: "mkdir", path: "/x")),
    .invalidEncoding, .unreadableEvent(message: "m"), .nonFiniteNumber,
  ]

  private static let pathSamples: [PathError] = [
    .escape("m"),
    .invalidIdentifier(parameterName: "p", value: "v"),
  ]

  private static let workspaceSamples: [WorkspaceError] = [
    .unknownComponent(requested: "a", declared: "b"),
    .configurationParseFailure,
    .configurationSchemaFailure,
    .path(.escape("m")),
  ]

  private static func caseCount(_ error: EvidenceEventError) -> Int {
    switch error {
    case .ledgerDamaged, .idempotencyConflict, .invalidTransition, .expectedHeadMismatch,
         .lockTimeout, .fileAccess, .invalidEncoding, .unreadableEvent, .nonFiniteNumber: 9
    }
  }

  private static func caseCount(_ error: PathError) -> Int {
    switch error {
    case .escape, .invalidIdentifier: 2
    }
  }

  private static func caseCount(_ error: WorkspaceError) -> Int {
    switch error {
    case .unknownComponent, .configurationParseFailure, .configurationSchemaFailure, .path: 4
    }
  }

  /// The case's name, without its payload.
  private static func caseName(_ error: some Error) -> Substring {
    String(describing: error).prefix { character in
      character != "("
    }
  }

  @Test
  func `every case of the sampled error enums is sampled`() throws {
    let evidence = try #require(Self.evidenceSamples.first)
    let path = try #require(Self.pathSamples.first)
    let workspace = try #require(Self.workspaceSamples.first)

    #expect(Set(Self.evidenceSamples.map(Self.caseName)).count == Self.caseCount(evidence))
    #expect(Set(Self.pathSamples.map(Self.caseName)).count == Self.caseCount(path))
    #expect(Set(Self.workspaceSamples.map(Self.caseName)).count == Self.caseCount(workspace))
  }

  @Test
  func `every code a Swift error can raise is mapped as TypeScript maps it, or known unmapped`() {
    var unaccounted: [String] = []
    let sampledCodes = Self.evidenceSamples.map(\.code) + Self.pathSamples.map(\.code)
      + Self.workspaceSamples.map(\.code)
    for code in sampledCodes
      where PublicErrorCodeMap.publicCode(forStringCode: code) == nil
      && !Self.knownUnmappedCodes.contains(code)
    {
      unaccounted.append(code)
    }
    for code in LedgerChainErrorCode.allCases
      where PublicErrorCode(rawValue: code.rawValue) == nil
    {
      unaccounted.append(code.rawValue)
    }
    for code in MarkerErrorCode.allCases where PublicErrorCodeMap.publicCode(for: code) == nil {
      unaccounted.append(code.rawValue)
    }
    for code in RegistryErrorCode.allCases where PublicErrorCodeMap.publicCode(for: code) == nil {
      unaccounted.append(code.rawValue)
    }
    for code in EvidenceErrorCode.allCases where PublicErrorCodeMap.publicCode(for: code) == nil {
      unaccounted.append(code.rawValue)
    }
    for code in SwiftFunctionErrorCode.allCases
      where PublicErrorCodeMap.publicCode(for: code) == nil
    {
      unaccounted.append(code.rawValue)
    }
    for code in SignatureFailureCode.allCases
      where PublicErrorCodeMap.publicCode(for: code) == nil
    {
      unaccounted.append(code.rawValue)
    }

    #expect(unaccounted.isEmpty)
    // No known-unmapped code may secretly be mapped: the list mirrors a gap.
    let secretlyMapped = Self.knownUnmappedCodes.filter { code in
      PublicErrorCodeMap.publicCode(forStringCode: code) != nil
    }
    #expect(secretlyMapped.isEmpty)
  }
}

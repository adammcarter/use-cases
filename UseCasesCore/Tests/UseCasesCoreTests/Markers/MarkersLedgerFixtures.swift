import Testing
@testable import UseCasesCore

/// Access to the generated TypeScript corpus in ``MarkersLedgerGoldenCorpus``:
/// the registry, the ledgers, their hashes and their signatures.
///
/// Inputs that canonical equivalence could merge arrive as JSON TEXT and are
/// parsed here by ``JSONParser``, so the parser is always part of what a case
/// exercises — a value built by hand in Swift would skip the layer where a
/// merge would happen.
enum MarkersLedgerFixtures {
  static let corpus: Result<JSONValue, SchemaError> = {
    do throws(SchemaError) {
      return try .success(JSONParser.parse(MarkersLedgerGoldenCorpus.json))
    } catch {
      return .failure(error)
    }
  }()

  static func root() throws -> JSONValue {
    try corpus.get()
  }

  static func section(_ name: String) throws -> [JSONValue] {
    try #require(root()[name]?.arrayValue, "corpus has no section \(name)")
  }

  static func entry(
    _ caseName: String,
    in sectionName: String,
  ) throws -> JSONValue {
    let match = try section(sectionName).first { candidate in
      candidate["name"]?.stringValue == caseName
    }
    return try #require(match, "corpus section \(sectionName) has no case \(caseName)")
  }

  /// Parse the JSON text stored under `key`.
  static func parsed(
    _ value: JSONValue,
    _ key: String,
  ) throws -> JSONValue {
    try JSONParser.parse(MarkersFixtures.string(value, key))
  }

  static func string(
    _ value: JSONValue,
    _ key: String,
  ) throws -> String {
    try MarkersFixtures.string(value, key)
  }

  static func strings(
    _ value: JSONValue,
    _ key: String,
  ) throws -> [String] {
    try MarkersFixtures.strings(value, key)
  }

  static func wire(_ value: JSONValue) -> String {
    JSONWriter.encode(value)
  }

  /// A named keypair's PEM text.
  static func pem(
    _ keypair: String,
    _ form: String,
  ) throws -> String {
    let keys = try #require(root()["keys"]?[keypair])
    return try string(keys, form)
  }

  /// The resolver a corpus case names, rebuilt on the Swift side.
  static func resolver(_ specification: JSONValue) throws -> PublicKeyResolver {
    switch try string(specification, "kind") {
    case "none":
      return { _, _ in nil }
    case "single":
      let pem = try string(specification, "pem")
      return { _, _ in pem }
    default:
      let keyringValue = try #require(specification["keyring"])
      return try Keyring.parse(keyringValue, sourcePath: nil).publicKeyResolver()
    }
  }
}

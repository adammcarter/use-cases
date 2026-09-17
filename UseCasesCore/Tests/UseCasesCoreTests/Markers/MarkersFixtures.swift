import Testing
@testable import UseCasesCore

/// Access to the generated TypeScript corpus in ``MarkersGoldenCorpus``.
///
/// Expected results are compared as wire bytes: both sides are written with
/// ``JSONWriter`` in document order, so a value, a key or a key ORDER that
/// differs from what the TypeScript returned fails the comparison.
enum MarkersFixtures {
  /// The whole corpus, parsed once.
  static let corpus: Result<JSONValue, SchemaError> = {
    do throws(SchemaError) {
      return try .success(JSONParser.parse(MarkersGoldenCorpus.json))
    } catch {
      return .failure(error)
    }
  }()

  /// Every case in the named section, in corpus order.
  static func section(_ name: String) throws -> [JSONValue] {
    let root = try corpus.get()
    return try #require(root[name]?.arrayValue, "corpus has no section \(name)")
  }

  /// The single case called `caseName` in the named section.
  static func entry(
    _ caseName: String,
    in sectionName: String,
  ) throws -> JSONValue {
    let match = try section(sectionName).first { candidate in
      candidate["name"]?.stringValue == caseName
    }
    return try #require(match, "corpus section \(sectionName) has no case \(caseName)")
  }

  /// The top-level object of constants the TypeScript exports.
  static func constants() throws -> JSONObject {
    let root = try corpus.get()
    return try #require(root["constants"]?.objectValue)
  }

  static func string(
    _ value: JSONValue,
    _ key: String,
  ) throws -> String {
    try #require(value[key]?.stringValue, "missing string \(key)")
  }

  static func optionalString(
    _ value: JSONValue,
    _ key: String,
  ) -> String? {
    value[key]?.stringValue
  }

  static func integer(
    _ value: JSONValue,
    _ key: String,
  ) throws -> Int {
    let number = try #require(value[key]?.numberValue, "missing number \(key)")
    return Int(number)
  }

  static func strings(
    _ value: JSONValue,
    _ key: String,
  ) throws -> [String] {
    let array = try #require(value[key]?.arrayValue, "missing array \(key)")
    return try array.map { element in
      try #require(element.stringValue)
    }
  }

  /// The `config` member of a case, as the Swift configuration type.
  static func configuration(_ value: JSONValue) -> CommentPrefixConfiguration? {
    guard let object = value["config"]?.objectValue else {
      return nil
    }
    guard let extensions = object["extensions"]?.objectValue else {
      return CommentPrefixConfiguration(extensions: nil)
    }
    var map: [String: String] = [:]
    for pair in extensions.pairs {
      map[pair.key] = pair.value.stringValue
    }
    return CommentPrefixConfiguration(extensions: map)
  }

  /// Wire bytes for comparison.
  static func wire(_ value: JSONValue) -> String {
    JSONWriter.encode(value)
  }

  /// The UTF-8 bytes of `text` in `[start, end)`, decoded back to a string.
  static func byteSlice(
    _ text: String,
    start: Int,
    end: Int,
  ) throws -> String {
    let bytes = Array(text.utf8)
    return try #require(String(bytes: bytes[start ..< end], encoding: .utf8))
  }
}

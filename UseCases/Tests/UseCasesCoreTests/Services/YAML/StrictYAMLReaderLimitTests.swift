import Testing
@testable import UseCasesCore

struct StrictYAMLReaderLimitTests {
  private let reader = StrictYAMLReader()

  private static func nested(
    _ shape: String,
    levels: Int,
  ) -> String {
    switch shape {
    case "flow lists":
      String(repeating: "[", count: levels) + String(repeating: "]", count: levels)
    case "flow mappings":
      String(repeating: "{a: ", count: levels) + "1" + String(repeating: "}", count: levels)
    case "inline lists":
      String(repeating: "- ", count: levels) + "x\n"
    case "block lists":
      lines(levels: levels) { _ in "-" } + " x\n"
    case "block mappings":
      lines(levels: levels) { _ in "a:" } + " 1\n"
    default:
      lines(levels: levels, marker: alternatingMarker) + " x\n"
    }
  }

  private static func alternatingMarker(_ level: Int) -> String {
    level.isMultiple(of: 2) ? "a:" : "-"
  }

  /// One level per line, each indented under the last, the final one left open for a value.
  private static func lines(
    levels: Int,
    marker: (Int) -> String,
  ) -> String {
    var text = ""

    for level in 0 ..< levels {
      text += String(repeating: " ", count: level * 2) + marker(level)
      text += level == levels - 1 ? "" : "\n"
    }

    return text
  }

  private static let shapes = [
    "flow lists", "flow mappings", "inline lists", "block lists", "block mappings", "mixed",
  ]

  @Test(arguments: shapes)
  func `a file nested 64 levels deep reads`(shape: String) {
    let result = reader.attempt(Self.nested(shape, levels: 64))

    #expect(result.failure == nil)
  }

  @Test(arguments: shapes)
  func `a file nested 65 levels deep is refused`(shape: String) throws {
    let error = try #require(reader.attempt(Self.nested(shape, levels: 65)).failure)

    guard case let .limitExceeded(_, limit) = error else {
      Issue.record("\(shape) was refused as \(error)")
      return
    }

    #expect(limit == .nesting(maximum: 64))
    #expect(error.message.contains("nested deeper than 64 levels"))
    #expect(error.message.hasPrefix("use-cases/a.yml:"))
  }

  @Test(arguments: shapes)
  func `a file nested 5,000 levels deep is refused without crashing`(shape: String) {
    let error = reader.attempt(Self.nested(shape, levels: 5000)).failure

    #expect(error == .limitExceeded(
      error?.location ?? YAMLLocation(file: "", line: 0),
      .nesting(maximum: 64),
    ))
  }

  @Test
  func `the line of a too-deep file is the line that goes past the limit`() {
    let error = reader.attempt(Self.nested("block mappings", levels: 70)).failure

    #expect(error?.line == 65)
  }

  @Test
  func `a settings file is held to the same depth`() {
    let text = Self.nested("flow lists", levels: 65)

    #expect(reader.attempt(text, kind: .settings).failure != nil)
  }

  @Test
  func `a limit can be set when the reader is made`() {
    let strict = StrictYAMLReader(limits: YAMLReadingLimits(nesting: 2, values: 100_000))

    #expect(strict.attempt("[[x]]").failure == nil)
    #expect(strict.attempt("[[[x]]]").failure != nil)
  }

  @Test
  func `aliases that wrap one another deeper than the limit are refused`() throws {
    var text = "l0: &l0 [x]\n"

    for level in 1 ..< 70 {
      text += "l\(level): &l\(level) [*l\(level - 1)]\n"
    }

    let error = try #require(reader.attempt(text).failure)

    guard case .limitExceeded(_, .nesting) = error else {
      Issue.record("refused as \(error)")
      return
    }
  }

  @Test
  func `a nested alias bomb is refused with the line of the alias`() throws {
    let ten = "[" + Array(repeating: "x", count: 10).joined(separator: ", ") + "]"
    var text = "a: &a \(ten)\n"

    for (previous, name) in zip("abcdefg", "bcdefgh") {
      let references = Array(repeating: "*\(previous)", count: 10).joined(separator: ", ")
      text += "\(name): &\(name) [\(references)]\n"
    }

    let error = try #require(reader.attempt(text).failure)

    #expect(error == .limitExceeded(
      YAMLLocation(file: "use-cases/a.yml", line: 5),
      .aliasValues(maximum: 100_000),
    ))
    #expect(error.message == "use-cases/a.yml:5: aliases here expand to more than 100,000 values")
  }

  @Test
  func `an alias file that expands moderately is read`() {
    let items = Array(repeating: "x", count: 100).joined(separator: ", ")
    var text = "base: &base [\(items)]\n"

    for number in 0 ..< 100 {
      text += "copy\(number): *base\n"
    }

    let result = reader.attempt(text)

    #expect(result.failure == nil)
  }

  @Test
  func `a value limit can be set when the reader is made`() {
    let strict = StrictYAMLReader(limits: YAMLReadingLimits(nesting: 64, values: 5))

    #expect(strict.attempt("a: 1\nb: 2\n").failure == nil)
    #expect(strict.attempt("a: 1\nb: 2\nc: 3\n").failure != nil)
  }

  @Test
  func `every scalar, list and mapping counts as a value, keys included`() {
    let strict = StrictYAMLReader(limits: YAMLReadingLimits(nesting: 64, values: 7))

    // A mapping, two keys and two values, and a list with two items: seven values.
    #expect(strict.attempt("a: 1\nb: [2, 3]\n").failure == nil)
    #expect(strict.attempt("a: 1\nb: [2, 3, 4]\n").failure != nil)
  }

  @Test
  func `crossing the limit inside an alias names the alias, and elsewhere names the file`() {
    let strict = StrictYAMLReader(limits: YAMLReadingLimits(nesting: 64, values: 7))

    let insideAlias = strict.attempt("a: &a [1, 2]\nb: *a\n").failure
    let outside = strict.attempt("a: 1\nb: 2\nc: 3\nd: 4\n").failure

    #expect(insideAlias == .limitExceeded(
      YAMLLocation(file: "use-cases/a.yml", line: 2),
      .aliasValues(maximum: 7),
    ))
    #expect(outside == .limitExceeded(
      YAMLLocation(file: "use-cases/a.yml", line: 4),
      .values(maximum: 7),
    ))
  }

  @Test
  func `a file with exactly 100,000 values and no aliases reads`() {
    // The list is one value and each item another: 99,999 items make 100,000.
    #expect(reader.attempt(Self.list(items: 99999)).failure == nil)
  }

  @Test
  func `a file with 100,001 values and no aliases is refused`() {
    let error = reader.attempt(Self.list(items: 100_000)).failure

    #expect(error == .limitExceeded(
      YAMLLocation(file: "use-cases/a.yml", line: 100_000),
      .values(maximum: 100_000),
    ))
    #expect(error?.message == "use-cases/a.yml:100000: this file holds more than 100,000 values")
  }

  @Test
  func `a mapping counts its keys as well as its values`() {
    var fits = ""
    var over = ""

    // The mapping is one value and each entry two: 49,999 entries make 99,999 values.
    for number in 0 ..< 49999 {
      fits += "k\(number): v\n"
    }

    for number in 0 ..< 50000 {
      over += "k\(number): v\n"
    }

    #expect(reader.attempt(fits).failure == nil)
    #expect(reader.attempt(over).failure != nil)
  }

  private static func list(items: Int) -> String {
    var text = ""

    for _ in 0 ..< items {
      text += "- x\n"
    }

    return text
  }
}

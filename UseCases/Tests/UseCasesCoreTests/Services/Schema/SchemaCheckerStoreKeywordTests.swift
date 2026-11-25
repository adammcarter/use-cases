import Testing
@testable import UseCasesCore

/// The keywords the results-store schemas add to the ones the authored schemas use: a `type`
/// written as a list, `maximum`, `maxItems`, `dependentRequired` and `format: date-time`.
struct SchemaCheckerStoreKeywordTests {
  @Test(arguments: [
    (#"{"type":["string","null"]}"#, "null", true),
    (#"{"type":["string","null"]}"#, #""x""#, true),
    (#"{"type":["string","null"]}"#, "1", false),
    (#"{"type":["integer","string"]}"#, "1.0", true),
    (#"{"type":["integer","string"]}"#, "1.5", false),
    (#"{"type":["object"]}"#, "[]", false),
  ])
  func `a value of any of the listed types satisfies type`(
    schema: String,
    value: String,
    isValid: Bool,
  ) throws {
    let checker = try SchemaChecker(schema: authored(schema))

    #expect(try checker.check(authored(value)).isEmpty == isValid)
  }

  @Test
  func `a failure of a listed type names every type`() throws {
    let checker = try SchemaChecker(schema: authored(#"{"type":["string","null"]}"#))

    let failures = try checker.check(authored("1"))

    #expect(failures.map(\.description) == ["1 is not of type 'string', 'null'"])
  }

  @Test(arguments: [
    ("1", true),
    ("0", true),
    ("0.5", true),
    ("1.5", false),
    ("2", false),
    ("-3", true),
    (#""2""#, true),
  ])
  func `a number above the maximum is refused`(
    value: String,
    isValid: Bool,
  ) throws {
    let checker = try SchemaChecker(schema: authored(#"{"maximum":1}"#))

    #expect(try checker.check(authored(value)).isEmpty == isValid)
  }

  @Test
  func `a number above the maximum says so`() throws {
    let checker = try SchemaChecker(schema: authored(#"{"maximum":9007199254740991}"#))

    let failures = try checker.check(authored("9007199254740992"))

    #expect(failures.map(\.keyword) == [.maximum])
    #expect(failures.map(\.message) == [
      "9007199254740992 is greater than the maximum of 9007199254740991",
    ])
  }

  @Test(arguments: [
    ("[]", true),
    ("[1]", true),
    ("[1,2]", false),
    (#""ab""#, true),
    ("{}", true),
  ])
  func `an array longer than maxItems is refused`(
    value: String,
    isValid: Bool,
  ) throws {
    let checker = try SchemaChecker(schema: authored(#"{"maxItems":1}"#))

    #expect(try checker.check(authored(value)).isEmpty == isValid)
  }

  @Test
  func `an array longer than maxItems says so`() throws {
    let checker = try SchemaChecker(schema: authored(#"{"maxItems":0}"#))

    let failures = try checker.check(authored("[1]"))

    #expect(failures.map(\.keyword) == [.maxItems])
    #expect(failures.map(\.message) == ["[1] is too long (at most 0 items)"])
  }

  @Test(arguments: [
    (#"{"exit_code":1,"command":["x"]}"#, true),
    (#"{"command":["x"]}"#, true),
    (#"{}"#, true),
    (#"{"exit_code":1}"#, false),
    (#"{"seconds":1}"#, false),
    (#"{"seconds":1,"exit_code":1}"#, false),
    (#"[]"#, true),
  ])
  func `a member that is written needs the members it depends on`(
    value: String,
    isValid: Bool,
  ) throws {
    let schema = #"{"dependentRequired":{"exit_code":["command"],"seconds":["command"]}}"#
    let checker = try SchemaChecker(schema: authored(schema))

    #expect(try checker.check(authored(value)).isEmpty == isValid)
  }

  @Test
  func `a missing dependency is named with the member that needs it`() throws {
    let checker = try SchemaChecker(
      schema: authored(#"{"dependentRequired":{"exit_code":["command"]}}"#),
    )

    let failures = try checker.check(authored(#"{"exit_code":1}"#))

    #expect(failures.map(\.keyword) == [.dependentRequired])
    #expect(failures.map(\.message) == ["'command' is a dependency of 'exit_code'"])
  }

  @Test(arguments: [
    #"{"dependentRequired":[]}"#,
    #"{"dependentRequired":{"a":"b"}}"#,
    #"{"dependentRequired":{"a":[1]}}"#,
    #"{"maximum":"1"}"#,
    #"{"maxItems":-1}"#,
    #"{"maxItems":1.5}"#,
  ])
  func `a store keyword whose value is the wrong kind is refused`(schema: String) throws {
    let value = try authored(schema)

    #expect(throws: SchemaCompilerError.self) {
      try SchemaChecker(schema: value)
    }
  }

  @Test
  func `a date-time is checked when the schema asks for one`() throws {
    let checker = try SchemaChecker(schema: authored(#"{"format":"date-time"}"#))

    #expect(try checker.check(authored(#""2026-09-25T12:34:56Z""#)).isEmpty)
    #expect(try checker.check(authored(#""yesterday""#)).map(\.keyword) == [.format])
    #expect(try checker.check(authored("1")).isEmpty)
  }
}

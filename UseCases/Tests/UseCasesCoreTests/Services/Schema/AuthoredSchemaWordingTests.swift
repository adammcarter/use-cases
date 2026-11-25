import Testing
@testable import UseCasesCore

/// The wording the acceptance suite pins (`UseCases/Acceptance`), the two proofs the
/// published patterns must give, and the groups schema, which `validate.py` has no inline
/// samples for.
struct AuthoredSchemaWordingTests {
  static let fingerprint = String(repeating: "a", count: 64)

  @Test(arguments: [
    (
      AuthoredSchema.useCases,
      #"{"use_cases":[{"id":"ui","title":42}]}"#,
      "42 is not of type 'string' at use_cases/0/title",
    ),
    (
      .useCases,
      #"{"use_cases":[{"id":"toggle\n","title":"Dark mode"}]}"#,
      "'toggle\\n' is not allowed at use_cases/0/id",
    ),
    (
      .useCases,
      """
      {"use_cases":[{"id":"ui","title":"Dark mode","approved":{"by":"Sam","on":"2026-02-30",\
      "behaviour":"\(AuthoredSchemaWordingTests.fingerprint)"}}]}
      """,
      "'2026-02-30' is not a 'date' at use_cases/0/approved/on",
    ),
    (
      .bridge,
      """
      {"schema_version":1,"validations":[{"id":"a","transformer":"x"},\
      {"id":"b","transformer":"../outside/tool"}]}
      """,
      "'../outside/tool' is not allowed at validations/1/transformer",
    ),
    (
      .bridge,
      """
      {"schema_version":1,"validations":[{"id":"a","transformer":"x"},\
      {"id":"b","transformer":"x","working_dir":".."}]}
      """,
      "'..' is not allowed at validations/1/working_dir",
    ),
    (
      .bridge,
      """
      {"schema_version":1,"validations":[{"id":"a","transformer":"x"},\
      {"id":"b","transformer":"x","working_dir":".use-cases"}]}
      """,
      "'.use-cases' is not allowed at validations/1/working_dir",
    ),
    (
      .useCaseGroups,
      #"{"schema_version":1,"groups":{"g":{"include":{"globs":["app.log*"]}}}}"#,
      "'app.log*' is not allowed at groups/g/include/globs/0",
    ),
    (
      .useCaseGroups,
      #"{"schema_version":1,"groups":{"Bad":{"include":{"ids":["app.auth.reset"]}}}}"#,
      "'Bad' is not allowed at groups",
    ),
    (
      .useCaseGroups,
      #"{"schema_version":1,"groups":{"g":{"members":["app.auth.reset"]}}}"#,
      "Additional properties are not allowed ('members' was unexpected) at groups/g",
    ),
    (
      .useCaseGroups,
      #"{"schema_version":1,"groups":{"g":{"include":{"tags":["x"]}}}}"#,
      "Additional properties are not allowed ('tags' was unexpected) at groups/g/include",
    ),
    (
      .useCaseGroups,
      #"{"groups":{}}"#,
      "'schema_version' is a required property",
    ),
    (
      .useCaseGroups,
      #"{"schema_version":2,"groups":{}}"#,
      "2 is not allowed at schema_version",
    ),
    (
      .workspace,
      #"{"schema_version":1,"prefix":"Shop"}"#,
      "'Shop' is not allowed at prefix",
    ),
    (
      .useCases,
      #"{"prefix":"calc.add\n","use_cases":[{"id":"ui","title":"Dark mode"}]}"#,
      "'calc.add\\n' is not allowed at prefix",
    ),
    (
      .useCases,
      """
      {"use_cases":[{"id":"ui","title":"Dark mode","bindings":[{"id":"x","kind":"manual",\
      "locator":{"file":"a\\u0001b"}}]}]}
      """,
      "'a\\u0001b' is not allowed at use_cases/0/bindings/0/locator/file",
    ),
  ])
  func `the failure reads the way the acceptance suite expects`(
    schema: AuthoredSchema,
    json: String,
    expected: String,
  ) throws {
    let checker = try BundledSchemaLoader().loadChecker(for: schema)

    let descriptions = try checker.check(authored(json)).map(\.description)

    #expect(descriptions == [expected])
  }

  @Test
  func `a plain project path is accepted where a control character is refused`() throws {
    let checker = try BundledSchemaLoader().loadChecker(for: .useCases)
    let json = """
    {"use_cases":[{"id":"ui","title":"Dark mode","bindings":[{"id":"x","kind":"manual",\
    "locator":{"file":"src/a.swift"}}]}]}
    """

    #expect(try checker.check(authored(json)).isEmpty)
  }

  @Test(arguments: [
    #"{"schema_version":1,"groups":{}}"#,
    """
    {"schema_version":1,"groups":{"release":{"description":"What ships",\
    "include":{"ids":["app.auth.reset"],"prefixes":["app.login"],\
    "globs":["app.*.success","**.success","*","**"]},"exclude":{"prefixes":["app.legacy"]}}}}
    """,
    #"{"schema_version":1,"groups":{"a":{},"b-2":{"include":{}}}}"#,
  ])
  func `a groups file the design allows has no failures`(json: String) throws {
    let checker = try BundledSchemaLoader().loadChecker(for: .useCaseGroups)

    #expect(try checker.check(authored(json)).isEmpty)
  }

  @Test(arguments: [
    #"{"schema_version":1,"groups":{"g":{"description":""}}}"#,
    #"{"schema_version":1,"groups":{"g":{"include":{"ids":["App.x"]}}}}"#,
    #"{"schema_version":1,"groups":{"g":{"include":{"prefixes":["app."]}}}}"#,
    #"{"schema_version":1,"groups":{"g":{"include":{"globs":["app.***x"]}}}}"#,
    #"{"schema_version":1,"groups":{"g":{"include":{"ids":"app.x"}}}}"#,
    #"{"schema_version":1,"groups":{"g\n":{}}}"#,
    #"{"schema_version":1,"groups":[]}"#,
    #"{"schema_version":1}"#,
  ])
  func `a groups file the design refuses has failures`(json: String) throws {
    let checker = try BundledSchemaLoader().loadChecker(for: .useCaseGroups)

    #expect(try !checker.check(authored(json)).isEmpty)
  }
}

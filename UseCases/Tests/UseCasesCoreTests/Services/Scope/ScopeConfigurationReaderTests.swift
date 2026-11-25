import Testing
@testable import UseCasesCore

struct ScopeConfigurationReaderTests {
  private let reader = ScopeConfigurationReader()

  private static let root = JSONMembers([
    "schema_version": "1",
    "root": "true",
    "prefix": #""shop""#,
  ])

  private func read(
    _ members: JSONMembers,
    role: ScopeRole,
    schemaChecked: Bool = true,
  ) throws -> ScopeConfiguration {
    let value = try schemaChecked
      ? checked(
        members.json,
        against: .workspace,
      )
      : authored(members.json)

    return try reader.read(
      value,
      file: workspacePath("use-cases.yml"),
      role: role,
    )
  }

  private func diagnostics(
    _ members: JSONMembers,
    role: ScopeRole,
    schemaChecked: Bool = true,
  ) throws -> [Diagnostic] {
    do {
      _ = try read(
        members,
        role: role,
        schemaChecked: schemaChecked,
      )
    } catch let ScopeConfigurationReadingError.invalid(diagnostics) {
      return diagnostics
    }

    return []
  }

  @Test
  func `a root with only its version, root marker and prefix gets every default`() throws {
    let configuration = try read(Self.root, role: .root)

    #expect(configuration.schemaVersion == 1)
    #expect(configuration.declaresRoot)
    #expect(configuration.prefix?.text == "shop")
    #expect(configuration.useCasesDirectory.text == "use-cases")
    #expect(configuration.rootSettings == .standard)
  }

  @Test
  func `a child scope without a prefix passes its parent's namespace through`() throws {
    let configuration = try read(
      JSONMembers(["schema_version": "1"]),
      role: .child,
    )

    #expect(configuration.prefix == nil)
    #expect(!configuration.declaresRoot)
    #expect(configuration.rootSettings == nil)
  }

  @Test
  func `a schema version written 1.0 is read, as the schema allows`() throws {
    let configuration = try read(
      Self.root.setting("schema_version", "1.0"),
      role: .root,
    )

    #expect(configuration.schemaVersion == 1)
  }

  @Test(arguments: ["auth", "payments.card", "oauth2", "3d"])
  func `a prefix is read as a namespace`(text: String) throws {
    let configuration = try read(
      Self.root.setting("prefix", "\"\(text)\""),
      role: .root,
    )

    #expect(configuration.prefix?.text == text)
  }

  @Test(arguments: ["services/use-cases", "use-cases", ".", "a b", "Cases"])
  func `a use_cases_dir inside the scope is read as written`(text: String) throws {
    let configuration = try read(
      Self.root.setting("use_cases_dir", "\"\(text)\""),
      role: .root,
    )

    #expect(configuration.useCasesDirectory.text == text)
  }

  @Test(arguments: ["../shared", "/etc", "C:use", "a/../../b", "use-cases/.."])
  func `a use_cases_dir that leaves the scope is refused in the scope's words`(
    text: String,
  ) throws {
    let found = try diagnostics(
      Self.root.setting("use_cases_dir", "\"\(text)\""),
      role: .root,
    )

    let message = try #require(found.first?.message)
    #expect(found.count == 1)
    #expect(message.contains("use_cases_dir"))
    #expect(message.contains("'\(text)' leaves the scope"))
  }

  @Test(arguments: ["./use-cases", "a//b", "use-cases/", "a\\\\b"])
  func `a use_cases_dir spelled in a non-canonical way is refused`(text: String) throws {
    let found = try diagnostics(
      Self.root.setting("use_cases_dir", "\"\(text)\""),
      role: .root,
    )

    #expect(found.count == 1)
    #expect(found.first?.code == .invalidValue)
  }

  @Test
  func `the root's freshness, exclusions and sign-off are read`() throws {
    let configuration = try read(
      Self.root
        .setting(
          "freshness",
          #"{"binding_identity":"content-and-locator","normalization":{"ignore":["whitespace"]}}"#,
        )
        .setting("discovery", #"{"exclude":["generated/**","**/node_modules/**"]}"#)
        .setting("sign_off", #""required""#),
      role: .root,
    )
    let settings = try #require(configuration.rootSettings)

    #expect(settings.freshness.bindingIdentity == .contentAndLocator)
    #expect(settings.freshness.ignoring == [.whitespace])
    #expect(
      try settings.discoveryExclusions
        == [
          PathPattern(validating: "generated/**"),
          PathPattern(validating: "**/node_modules/**"),
        ],
    )
    #expect(settings.signOff == .required)
  }

  @Test
  func `a root with no freshness ignores line endings, and a written empty ignore is exact`(
  ) throws {
    let omitted = try read(Self.root, role: .root)
    let exact = try read(
      Self.root.setting("freshness", #"{"normalization":{"ignore":[]}}"#),
      role: .root,
    )

    #expect(omitted.rootSettings?.freshness.ignoring == [.lineEndings])
    #expect(exact.rootSettings?.freshness.ignoring.isEmpty == true)
  }

  @Test
  func `built-in exclusions are not folded into the root's own`() throws {
    let configuration = try read(Self.root, role: .root)

    #expect(configuration.rootSettings?.discoveryExclusions.isEmpty == true)
  }

  @Test(arguments: ["a**", "/x", "./x", "a//b", "..", ".", "a\\\\b"])
  func `a malformed exclusion pattern is refused with its place`(pattern: String) throws {
    let found = try diagnostics(
      Self.root.setting(
        "discovery",
        JSONMembers(["exclude": "[\(jsonString("ok/**")),\(jsonString(pattern))]"]).json,
      ),
      role: .root,
    )

    let message = try #require(found.first?.message)
    #expect(found.count == 1)
    #expect(message.hasPrefix("discovery.exclude[1]:"))
  }

  @Test(
    arguments: [
      ("freshness", #"{"binding_identity":"content"}"#),
      ("discovery", #"{"exclude":["generated/**"]}"#),
      ("sign_off", #""required""#),
    ],
  )
  func `a child scope that sets a root-only setting is INVALID`(
    case example: (key: String, json: String),
  ) throws {
    let found = try diagnostics(
      JSONMembers(["schema_version": "1", "prefix": #""auth""#])
        .setting(example.key, example.json),
      role: .child,
    )

    #expect(found.count == 1)
    #expect(found.first?.code == .rootOnlySetting)
    #expect(found.first?.severity == .error)
    #expect(found.first?.message.contains("\(example.key) is root-only") == true)
    #expect(found.first?.file.text == "use-cases.yml")
  }

  @Test
  func `a child scope that sets all three root-only settings is told about each`() throws {
    let found = try diagnostics(
      JSONMembers(["schema_version": "1"])
        .setting("sign_off", #""required""#)
        .setting("freshness", "{}")
        .setting("discovery", "{}"),
      role: .child,
    )

    let messages = found.map(\.message)
    #expect(messages.count == 3)
    #expect(messages[0].hasPrefix("discovery is root-only"))
    #expect(messages[1].hasPrefix("freshness is root-only"))
    #expect(messages[2].hasPrefix("sign_off is root-only"))
  }

  @Test
  func `the root may set every root-only setting`() throws {
    let configuration = try read(
      Self.root.setting("sign_off", #""required""#).setting("freshness", "{}"),
      role: .root,
    )

    #expect(configuration.rootSettings?.signOff == .required)
  }

  @Test
  func `a child scope's own prefix and use_cases_dir are its own`() throws {
    let configuration = try read(
      JSONMembers(["schema_version": "1", "prefix": #""auth""#, "use_cases_dir": #""cases""#]),
      role: .child,
    )

    #expect(configuration.prefix?.text == "auth")
    #expect(configuration.useCasesDirectory.text == "cases")
  }

  @Test
  func `every independent problem in a file is reported, sorted`() throws {
    let found = try diagnostics(
      JSONMembers(["schema_version": "1", "prefix": #""Bad""#, "use_cases_dir": #""../x""#]),
      role: .child,
      schemaChecked: false,
    )

    #expect(found.count == 2)
    #expect(found == found.sorted())
  }

  @Test(arguments: ["[]", "1", #""x""#, "null"])
  func `a value that is not a mapping is refused`(json: String) throws {
    let value = try authored(json)

    do {
      _ = try reader.read(
        value,
        file: workspacePath("use-cases.yml"),
        role: .root,
      )
      Issue.record("a value that is not a mapping was read")
    } catch let ScopeConfigurationReadingError.invalid(diagnostics) {
      #expect(diagnostics.count == 1)
      #expect(diagnostics.first?.message == "this must be a mapping")
    }
  }

  @Test
  func `a schema version that is missing or not a number is refused`() throws {
    let found = try diagnostics(
      JSONMembers(["schema_version": #""1""#]),
      role: .root,
      schemaChecked: false,
    )

    #expect(found.count == 1)
    #expect(found.first?.message.hasPrefix("schema_version:") == true)
  }
}

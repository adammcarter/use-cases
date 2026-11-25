import Testing
@testable import UseCasesCore

struct LinksRequestBuilderTests {
  private let fixture: WorkspaceFixture

  init() throws {
    fixture = try WorkspaceFixture()
    try fixture.writeUseCase()
  }

  private func request(settings: AuthoredValue? = nil) throws -> AuthoredObject {
    let document = try LinksRequestBuilder().request(
      for: fixture.loaded(),
      settings: settings,
    )
    let text = StoreJSONWriter().compact(document).utf8Text

    return try AuthoredObject(
      JSONReader().read(text),
      at: "",
    )
  }

  @Test
  func `the request says contract 1 and the links job`() throws {
    let request = try request()

    #expect(try request.requiredInteger("contract") == 1)
    #expect(try request.requiredString("job") == "links")
  }

  @Test
  func `it names every use case by its full id`() throws {
    let request = try request()
    let useCases = try request.objects("use_cases")

    #expect(
      try useCases.map { useCase in
        try useCase.requiredString("id")
      } == ["app.toggle"],
    )
  }

  @Test
  func `it names the workspace root as the code root`() throws {
    let request = try request()

    #expect(try request.requiredString("code_root") == fixture.directory.url.path)
  }

  @Test
  func `it lists what is Use Cases' own, sorted, for the transformer to leave alone`() throws {
    try fixture.write("use-cases-bridge.yml", "schema_version: 1\n")
    try fixture.write("use-case-groups.yml", "schema_version: 1\ngroups: {}\n")

    let request = try request()

    #expect(
      try request.strings("ignore") == [
        "use-case-groups.yml",
        "use-cases-bridge.yml",
        "use-cases.yml",
        "use-cases/toggle.yml",
      ],
    )
  }

  @Test
  func `settings go unchanged, or are an empty object when there are none`() throws {
    // The writer sorts members by key, so this is written in that order.
    let settings = AuthoredValue.object([
      AuthoredMember(key: "files", value: .string("test/**/*.js")),
      AuthoredMember(key: "limit", value: .integer(5)),
      AuthoredMember(key: "list", value: .array([.string("a"), .integer(1)])),
      AuthoredMember(key: "none", value: .null),
      AuthoredMember(key: "ratio", value: .number(0.5)),
      AuthoredMember(key: "strict", value: .boolean(true)),
    ])

    #expect(try request(settings: settings).value(for: "settings") == settings)
    #expect(try request().value(for: "settings") == .object([]))
  }

  @Test
  func `the request has the members of the published schema and no others`() throws {
    let request = try request()

    #expect(
      request.members.map(\.key).sorted() == [
        "code_root", "contract", "ignore", "job", "settings", "use_cases",
      ],
    )
  }
}

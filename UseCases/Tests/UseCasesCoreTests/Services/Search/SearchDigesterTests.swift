import Testing
@testable import UseCasesCore

struct SearchDigesterTests {
  private let fixture: SearchFixture
  private let digester = SearchDigester()

  init() throws {
    fixture = try SearchFixture()
  }

  private func digest(members: [String]? = nil) throws -> String {
    let loaded = try fixture.workspace.loaded()
    let status = try StatusJudge().judge(
      loaded,
      links: LinkResolver().resolveLinks(in: loaded),
    )

    return digester.digest(
      of: loaded,
      status: status,
      groupMembers: members,
    )
  }

  @Test
  func `the same use cases give the same digest`() throws {
    #expect(try digest() == digest())
  }

  @Test
  func `a changed use case, a changed status or changed members change it`() throws {
    let before = try digest()
    let withMembers = try digest(members: ["app.feed.post.like"])

    try fixture.record("app.feed.post.like")
    let afterVerdict = try digest()

    try fixture.workspace.write(
      "use-cases/settings.yml",
      "prefix: settings\nuse_cases:\n  - id: theme\n    title: Switch theme\n",
    )
    let afterEdit = try digest()

    #expect(Set([before, withMembers, afterVerdict, afterEdit]).count == 4)
  }

  @Test
  func `a group with no members is told apart from no group`() throws {
    #expect(try digest(members: []) != digest(members: nil))
  }

  @Test
  func `a seal depends on the parameters and on the state`() {
    let one = StoreJSONValue.members(["offset": .integer(1)])
    let two = StoreJSONValue.members(["offset": .integer(2)])

    #expect(digester.seal(of: one, state: "a") == digester.seal(of: one, state: "a"))
    #expect(digester.seal(of: one, state: "a") != digester.seal(of: two, state: "a"))
    #expect(digester.seal(of: one, state: "a") != digester.seal(of: one, state: "b"))
  }
}

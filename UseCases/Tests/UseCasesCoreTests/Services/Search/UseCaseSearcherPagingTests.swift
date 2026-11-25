import Foundation
import Testing
@testable import UseCasesCore

struct UseCaseSearcherPagingTests {
  private let fixture: SearchFixture

  init() throws {
    fixture = try SearchFixture()
  }

  private func nextToken(_ page: SearchPage) throws -> String {
    try #require(page.next)
  }

  @Test
  func `pages cover every match once, in order, and a page is never empty`() throws {
    let everything = try fixture.page(
      .words("the"),
      pageSize: "100",
    ).matches
    var pages: [SearchMatch] = []
    var page = try fixture.page(
      .words("the"),
      pageSize: "1",
    )

    while true {
      #expect(page.total == everything.count)
      #expect(page.offset == pages.count)
      #expect(!page.matches.isEmpty)
      pages += page.matches

      guard let next = page.next else {
        break
      }

      page = try fixture.page(of: .continuing(token: next))
    }

    #expect(pages == everything)
    #expect(pages.count > 2)
  }

  @Test
  func `the last page has no token`() throws {
    let page = try fixture.page(.words("the"), pageSize: "100")

    #expect(page.next == nil)
  }

  @Test
  func `a token carries the whole search`() throws {
    let first = try fixture.page(
      .words("the"),
      tiers: "core",
      fields: "scenarios",
      pageSize: "1",
    )
    let second = try fixture.page(of: .continuing(token: nextToken(first)))

    #expect(!second.matches.isEmpty)
    #expect(second.matches.allSatisfy { $0.valueTier == "core" })
    #expect(second.pageSize == 1)
  }

  @Test
  func `tokens are deterministic`() throws {
    let first = try fixture.page(.words("the"), pageSize: "1")
    let again = try fixture.page(.words("the"), pageSize: "1")

    #expect(first.next == again.next)
  }

  @Test
  func `a use case edited between pages refuses the next page`() throws {
    let token = try nextToken(fixture.page(.words("the"), pageSize: "1"))
    try fixture.workspace.write(
      "use-cases/feed/media.yml",
      "prefix: feed.media\nuse_cases:\n  - id: zoom\n    title: Zoom into a photo\n",
    )

    #expect(throws: UseCaseSearchError.changed) {
      try fixture.page(of: .continuing(token: token))
    }
  }

  @Test
  func `a verdict recorded between pages refuses the next page`() throws {
    let token = try nextToken(fixture.page(.words("the"), pageSize: "1"))

    try fixture.record("app.feed.post.like")

    #expect(throws: UseCaseSearchError.changed) {
      try fixture.page(of: .continuing(token: token))
    }
  }

  @Test
  func `nothing changing between pages keeps the token good`() throws {
    let token = try nextToken(fixture.page(.words("the"), pageSize: "1"))

    #expect(try fixture.page(of: .continuing(token: token)).offset == 1)
  }

  @Test
  func `a group whose members changed between pages refuses the next page`() throws {
    let token = try nextToken(fixture.page(
      .words("the"),
      group: "social",
      pageSize: "1",
    ))
    try fixture.workspace.write(
      "use-case-groups.yml",
      "schema_version: 1\ngroups:\n  social:\n    include: { prefixes: [app.feed] }\n",
    )

    #expect(throws: UseCaseSearchError.changed) {
      try fixture.page(of: .continuing(token: token))
    }
  }

  @Test
  func `a group gone between pages refuses the next page as changed`() throws {
    let token = try nextToken(fixture.page(
      .words("the"),
      group: "social",
      pageSize: "1",
    ))
    try fixture.workspace.write(
      "use-case-groups.yml",
      "schema_version: 1\ngroups:\n  other:\n    include: { prefixes: [app.feed] }\n",
    )

    #expect(throws: UseCaseSearchError.changed) {
      try fixture.page(of: .continuing(token: token))
    }
  }

  @Test
  func `an edited token is refused, however it was edited`() throws {
    let token = try nextToken(fixture.page(.words("the"), pageSize: "1"))
    let codec = SearchTokenCodec()
    let edited = try #require(codec.parameters(in: token).objectMembers)

    for (key, value) in [
      ("offset", AuthoredValue.integer(2)),
      ("page_size", .integer(2)),
      ("words", .array([.string("zoom")])),
      ("seal", .string("0")),
    ] {
      let members = edited.map { member in
        member.key == key ? AuthoredMember(key: key, value: value) : member
      }
      let forged = codec.token(for: members.storeValue)

      #expect(throws: UseCaseSearchError.changed) {
        try fixture.page(of: .continuing(token: forged))
      }
    }
  }

  @Test(arguments: ["garbage", "eyJ2IjoyfQ", "", "e30", "W10", "bnVsbA"])
  func `a token this command did not make is refused`(token: String) {
    #expect(throws: UseCaseSearchError.invalidToken) {
      try fixture.page(of: .continuing(token: token))
    }
  }

  @Test(arguments: ["0", "101", "-1", "2.5", "abc", "", "+5", "٣"])
  func `page size is 1 to 100`(size: String) {
    #expect(throws: UseCaseSearchError.pageSize(size)) {
      try fixture.page(.words("the"), pageSize: size)
    }
  }

  @Test(arguments: ["1", "20", "100"])
  func `a page size from 1 to 100 is taken`(size: String) throws {
    #expect(try fixture.page(.words("the"), pageSize: size).pageSize == Int(size))
  }
}

private extension AuthoredValue {
  var objectMembers: [AuthoredMember]? {
    guard case let .object(members) = self else {
      return nil
    }

    return members
  }
}

private extension [AuthoredMember] {
  var storeValue: StoreJSONValue {
    .object(map { member in
      StoreJSONMember(key: member.key, value: member.value.storeValue)
    })
  }
}

private extension AuthoredValue {
  var storeValue: StoreJSONValue {
    switch self {
    case let .string(text):
      .string(text)
    case let .integer(number):
      .integer(number)
    case let .number(number):
      .number(number)
    case let .boolean(flag):
      .boolean(flag)
    case .null:
      .null
    case let .array(items):
      .array(items.map(\.storeValue))
    case let .object(members):
      members.storeValue
    }
  }
}

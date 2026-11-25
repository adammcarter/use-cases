import Testing
@testable import UseCasesCore

struct ResolvedLinkOrderTests {
  private func order(_ links: [ResolvedLink]) -> [String] {
    links.inLinkOrder.map(\.key)
  }

  @Test
  func `links order by use case id, then implementation before routes, then binding id`() throws {
    let links = try [
      ResolvedLink.sample(useCase: "b.one", binding: "x"),
      ResolvedLink.sample(useCase: "a.two", route: "unit", binding: "a"),
      ResolvedLink.sample(useCase: "a.two", route: "ui", binding: "z"),
      ResolvedLink.sample(useCase: "a.two", binding: "z"),
      ResolvedLink.sample(useCase: "a.two", binding: "b"),
      ResolvedLink.sample(useCase: "a.one", binding: "q"),
    ]

    #expect(
      order(links) == [
        "a.one#q@src/a.swift:1",
        "a.two#b@src/a.swift:1",
        "a.two#z@src/a.swift:1",
        "a.two#ui.z@src/a.swift:1",
        "a.two#unit.a@src/a.swift:1",
        "b.one#x@src/a.swift:1",
      ],
    )
  }

  @Test
  func `links of one binding order by file bytes, then start line as a number`() throws {
    let links = try [
      ResolvedLink.sample(file: "src/b.swift", lines: 2 ... 2),
      ResolvedLink.sample(file: "src/a.swift", lines: 13 ... 13),
      ResolvedLink.sample(file: "src/a.swift", lines: 2 ... 2),
      ResolvedLink.sample(file: "Src/z.swift", lines: 1 ... 1),
      ResolvedLink.sample(file: "src/a.swift", lines: 7 ... 7),
    ]

    #expect(
      order(links) == [
        "app.toggle#code@Src/z.swift:1",
        "app.toggle#code@src/a.swift:2",
        "app.toggle#code@src/a.swift:7",
        "app.toggle#code@src/a.swift:13",
        "app.toggle#code@src/b.swift:2",
      ],
    )
  }

  @Test
  func `a dot sorts after a hyphen the way the bytes do`() throws {
    let links = try [
      ResolvedLink.sample(useCase: "a.b"),
      ResolvedLink.sample(useCase: "a-b"),
    ]

    #expect(order(links) == ["a-b#code@src/a.swift:1", "a.b#code@src/a.swift:1"])
  }

  @Test
  func `links that agree on everything but their end line keep a fixed order`() throws {
    let links = try [
      ResolvedLink.sample(lines: 1 ... 5),
      ResolvedLink.sample(lines: 1 ... 2),
    ]

    #expect(links.inLinkOrder.map(\.endLine) == [2, 5])
    #expect(links.reversed().inLinkOrder.map(\.endLine) == [2, 5])
  }
}

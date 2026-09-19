import Testing
@testable import UseCasesCLI

/// The usage catalog: the hand-written builtins, then every visible registry
/// command, and the prefix-then-group-then-everything selection help uses.
struct UsageCatalogTests {
  @Test
  func `lists the builtins then every visible command`() {
    let names = UsageCatalog.entries.map(\.name)

    #expect(Array(names.prefix(2)) == ["version", "init"])
    #expect(names.count == 2 + 43)
    #expect(!names.contains("doctor skills"))
  }

  @Test(arguments: [
    ([], 45),
    (["matrix"], 5),
    (["matrix", "list"], 1),
    (["matrix", "nothing"], 5),
    (["nothing"], 45),
    (["show"], 45),
    (["doctor"], 1),
    (["scan"], 1),
  ])
  func `selects by full prefix, then by group, then everything`(
    tokens: [String],
    count: Int,
  ) {
    #expect(UsageCatalog.select(tokens: tokens).count == count)
  }
}

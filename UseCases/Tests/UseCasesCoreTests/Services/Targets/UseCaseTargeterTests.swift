import Testing
@testable import UseCasesCore

struct UseCaseTargeterTests {
  private let fixture: WorkspaceFixture

  init() throws {
    fixture = try WorkspaceFixture()
    try fixture.write(
      "use-cases/shop.yml",
      YAMLSamples.file(
        prefix: "shop",
        YAMLSamples.useCase("pay"),
        YAMLSamples.useCase("pay-later"),
      ),
    )
    try fixture.write(
      "use-cases/pay.yml",
      YAMLSamples.file(
        prefix: "shop.pay",
        YAMLSamples.useCase("card"),
        YAMLSamples.useCase("wallet"),
      ),
    )
  }

  private func named(_ target: String) throws -> Set<String> {
    try UseCaseTargeter().identifiers(
      matching: target,
      in: fixture.loaded(),
    )
  }

  @Test
  func `an exact use case id names that use case alone, even when others start with it`() throws {
    #expect(try named("app.shop.pay") == ["app.shop.pay"])
  }

  @Test
  func `an id prefix names every use case under it, by full id`() throws {
    #expect(
      try named("app.shop") == [
        "app.shop.pay",
        "app.shop.pay-later",
        "app.shop.pay.card",
        "app.shop.pay.wallet",
      ],
    )
  }

  @Test
  func `the whole root prefix names every use case`() throws {
    #expect(try named("app").count == 4)
  }

  @Test
  func `a use case id with no use cases under it names itself`() throws {
    #expect(try named("app.shop.pay.card") == ["app.shop.pay.card"])
  }

  @Test(arguments: [
    "",
    "app.sho",
    "app.shop.pa",
    "app.shop.pay.car",
    "app.shop.pay.card.x",
    "App.shop",
    "nothing",
    ".",
    "app..shop",
  ])
  func `a target that is not a whole use case or a whole-segment prefix names nothing`(
    target: String,
  ) throws {
    #expect(throws: UseCaseTargetingError.unmatched(target: target)) {
      try named(target)
    }
  }

  @Test
  func `the refusal says what was typed`() {
    let error = UseCaseTargetingError.unmatched(target: "shop.nope")

    #expect(error.message.contains("no use case or id prefix"))
    #expect(error.message.contains("shop.nope"))
  }
}

import Testing
@testable import UseCasesCore

struct RecordOfferChoosingTests {
  private static let offers = [
    RecordOffer(
      useCase: "shop.pay",
      routes: [
        RecordRouteOffer(route: "unit-tests", steps: []),
        RecordRouteOffer(route: "unit-more", steps: []),
        RecordRouteOffer(route: "manual", steps: ["Look."]),
      ],
    ),
    RecordOffer(
      useCase: "shop.pay.card",
      routes: [RecordRouteOffer(route: "manual", steps: ["Pay by card."])],
    ),
    RecordOffer(
      useCase: "shop.cart",
      routes: [RecordRouteOffer(route: "1", steps: [])],
    ),
    RecordOffer(
      useCase: "1st",
      routes: [],
    ),
  ]

  private func useCase(_ answer: String) throws -> String {
    try RecordOffer.choose(
      answer,
      among: Self.offers,
    ).useCase
  }

  @Test(arguments: [
    ("1", "shop.pay"),
    ("2", "shop.pay.card"),
    ("3", "shop.cart"),
    ("shop.cart", "shop.cart"),
    ("shop.c", "shop.cart"),
    ("shop.pay.c", "shop.pay.card"),
  ])
  func `a use case is named by its number, its id or the start of one id`(
    answer: String,
    expected: String,
  ) throws {
    #expect(try useCase(answer) == expected)
  }

  @Test
  func `an id that is also the start of others is that use case alone`() throws {
    #expect(try useCase("shop.pay") == "shop.pay")
  }

  @Test
  func `an exact id wins over a number`() throws {
    let offers = [
      RecordOffer(useCase: "a", routes: []),
      RecordOffer(useCase: "2", routes: []),
      RecordOffer(useCase: "b", routes: []),
    ]

    #expect(try RecordOffer.choose("2", among: offers).useCase == "2")
  }

  @Test
  func `a number wins over the start of an id`() throws {
    // Answer 1 is the first use case, though `1st` also starts with it.
    #expect(try useCase("1") == "shop.pay")
  }

  @Test(arguments: ["0", "5", "99999999999999999999", "-1", "+1", "1.0", " 1"])
  func `a number outside the list is not a number`(answer: String) {
    #expect(throws: RecordingError.noUseCase(answer)) {
      try useCase(answer)
    }
  }

  @Test
  func `the start of several ids is an ambiguity that lists them, sorted`() {
    #expect(
      throws: RecordingError.ambiguousUseCase(
        "shop.",
        matching: ["shop.cart", "shop.pay", "shop.pay.card"],
      ),
    ) {
      try useCase("shop.")
    }
  }

  @Test
  func `an empty answer names nothing, even when one use case is offered`() {
    let single = [RecordOffer(useCase: "only", routes: [])]

    #expect(throws: RecordingError.noUseCase("")) {
      try RecordOffer.choose("", among: single)
    }
    #expect(throws: RecordingError.noUseCase("")) {
      try RecordOffer.choose("", among: [])
    }
  }

  @Test
  func `an answer that starts no id names nothing`() {
    #expect(throws: RecordingError.noUseCase("nope")) {
      try useCase("nope")
    }
  }

  @Test(arguments: [
    ("1", "unit-tests"),
    ("3", "manual"),
    ("manual", "manual"),
    ("unit-t", "unit-tests"),
    ("unit-m", "unit-more"),
  ])
  func `a route is named in the same ways`(
    answer: String,
    expected: String,
  ) throws {
    let offer = try #require(Self.offers.first)

    #expect(try offer.chooseRoute(answer).route == expected)
  }

  @Test
  func `the start of several routes is an ambiguity that names the use case`() throws {
    let offer = try #require(Self.offers.first)

    #expect(
      throws: RecordingError.ambiguousRoute(
        useCase: "shop.pay",
        route: "unit",
        matching: ["unit-more", "unit-tests"],
      ),
    ) {
      try offer.chooseRoute("unit")
    }
  }

  @Test
  func `a route that is not offered is told with its use case`() throws {
    let offer = try #require(Self.offers.first)

    #expect(
      throws: RecordingError.noRoute(
        useCase: "shop.pay",
        route: "x",
      ),
    ) {
      try offer.chooseRoute("x")
    }
  }

  @Test
  func `a route whose id is a number is that route before it is a position`() throws {
    let offer = try #require(Self.offers.first { $0.useCase == "shop.cart" })

    #expect(try offer.chooseRoute("1").route == "1")
  }
}

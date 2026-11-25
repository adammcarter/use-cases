import Testing
@testable import UseCasesCore

struct VerdictRecorderOfferTests {
  @Test
  func `a READY use case is offered with its routes and their steps`() throws {
    let fixture = try RecorderFixture()
    let loaded = try fixture.freshness.workspace.loaded()

    #expect(
      fixture.recorder.offers(in: loaded) == [
        RecordOffer(
          useCase: "app.toggle",
          routes: [
            RecordRouteOffer(route: "manual", steps: ["Check it."]),
            RecordRouteOffer(route: "unit-tests", steps: []),
          ],
        ),
      ],
    )
  }

  @Test
  func `a DRAFT use case is not offered`() throws {
    let fixture = try RecorderFixture(definitions: FreshnessSamples.definitions(isReady: false))
    let loaded = try fixture.freshness.workspace.loaded()

    #expect(fixture.recorder.offers(in: loaded).isEmpty)
  }
}

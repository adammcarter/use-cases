import Testing
@testable import UseCasesCore

/// The two messages for a sentinel with no partner name the way out for a file that holds marker
/// text as data (chapter 08).
struct MarkerPairingMessageTests {
  private func sentinel(
    _ kind: MarkerSentinelKind,
    line: Int,
  ) -> MarkerSentinel {
    MarkerSentinel(
      kind: kind,
      identifier: "shop.cart.add#add-item",
      tokenRange: 0 ..< 10,
      line: line,
    )
  }

  @Test
  func `a start never closed names the exclusion`() throws {
    let diagnostic = try Diagnostic.markerPairing(
      .neverClosed(sentinel(.start, line: 3)),
      in: WorkspacePath.at("tests/fixtures/sample.swift"),
    )

    #expect(
      diagnostic.description
        == "tests/fixtures/sample.swift:3: marker 'shop.cart.add#add-item' is never closed: "
        + "no '@use-case:end shop.cart.add#add-item' follows it; if this file holds marker text "
        + "as data, exclude it with discovery.exclude in use-cases.yml",
    )
  }

  @Test
  func `an end with no start names the exclusion`() throws {
    let diagnostic = try Diagnostic.markerPairing(
      .withoutStart(sentinel(.end, line: 9)),
      in: WorkspacePath.at("tests/fixtures/sample.swift"),
    )

    #expect(
      diagnostic.description
        == "tests/fixtures/sample.swift:9: the end of marker 'shop.cart.add#add-item' has no "
        + "start before it; if this file holds marker text as data, exclude it with "
        + "discovery.exclude in use-cases.yml",
    )
  }
}

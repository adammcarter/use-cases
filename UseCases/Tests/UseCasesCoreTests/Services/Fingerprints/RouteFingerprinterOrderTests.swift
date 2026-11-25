import Testing
@testable import UseCasesCore

/// The exact order of the arrays in the payload bytes (chapter 11 §89.5, §89.6). Comparing two
/// shuffles would pass whichever way the sort ran, so these read the bytes.
struct RouteFingerprinterOrderTests {
  private let fingerprinter = RouteFingerprinter()

  private func payload(
    policy: FreshnessPolicy? = nil,
    implementation: [LinkContribution] = [],
    resources: [ResourceContribution] = [],
  ) throws -> String {
    let input = try FingerprintSamples.vectorA().replacing(
      policy: policy,
      contributions: RouteContributions(
        implementation: implementation,
        resources: resources,
      ),
    )

    return try fingerprinter.payload(of: input).utf8Text
  }

  private func locatorRegion(
    file: String,
    start: Int,
  ) -> String {
    #"{"content":"# + FingerprintParts.written(digestEnding: "aa") + #","locator":{"end_byte":"#
      + String(start + 1) + #","file":""# + file + #"","start_byte":"# + String(start) + "}}"
  }

  @Test
  func `content mode writes regions in digest order`() throws {
    let high = try LinkRegionContribution(
      locator: FingerprintLocator(file: workspacePath("a.swift"), startByte: 0, endByte: 1),
      content: FingerprintParts.reference(digestEnding: "ff"),
    )
    let low = try LinkRegionContribution(
      locator: FingerprintLocator(file: workspacePath("b.swift"), startByte: 0, endByte: 1),
      content: FingerprintParts.reference(digestEnding: "01"),
    )
    let link = try LinkContribution(
      binding: BindingIdentifier(validating: "impl"),
      kind: .manual,
      regions: [high, low],
    )

    let text = try payload(implementation: [link])

    #expect(
      text.contains(
        #""regions":["# + FingerprintParts.written(digestEnding: "01") + ","
          + FingerprintParts.written(digestEnding: "ff") + "]",
      ),
    )
  }

  @Test
  func `content-and-locator mode writes regions by file, then start`() throws {
    let link = try FingerprintParts.link(
      "impl",
      kind: .marker,
      FingerprintParts.region(file: "b.swift", start: 5),
      FingerprintParts.region(file: "a.swift", start: 9),
      FingerprintParts.region(file: "b.swift", start: 0),
    )

    let text = try payload(
      policy: FingerprintSamples.strictPolicy,
      implementation: [link],
    )

    #expect(
      text.contains(
        #""regions":["# + locatorRegion(file: "a.swift", start: 9) + ","
          + locatorRegion(file: "b.swift", start: 0) + ","
          + locatorRegion(file: "b.swift", start: 5) + "]",
      ),
    )
  }

  @Test
  func `resources are written in path order`() throws {
    let users = try FingerprintParts.resource("fixtures/users.json", "{}")
    let config = try FingerprintParts.resource("config.json", "[]")

    let text = try payload(resources: [users, config])

    let configAt = try #require(text.range(of: #""file":"config.json""#))
    let usersAt = try #require(text.range(of: #""file":"fixtures/users.json""#))
    #expect(configAt.lowerBound < usersAt.lowerBound)
    #expect(text.contains(#""resources":[{"content":"#))
  }
}

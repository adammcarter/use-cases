import Testing
@testable import UseCasesCore

/// What chapter 11 §89.5 and §89.6 say about links and resources.
struct RouteFingerprinterLinkTests {
  private let fingerprinter = RouteFingerprinter()
  private let strict = FingerprintSamples.strictPolicy

  private func fingerprint(
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

    return try fingerprinter.fingerprint(of: input)
  }

  /// Whether the bytes of `text` hold the bytes of `needle`: `String.contains` treats a name in
  /// two Unicode forms as one.
  private func holds(
    _ text: String,
    _ needle: String,
  ) -> Bool {
    Array(text.utf8).firstRange(of: Array(needle.utf8)) != nil
  }

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

  @Test
  func `links are sorted by binding id`() throws {
    let text = try payload(
      implementation: [
        FingerprintParts.link("zeta", FingerprintParts.region("z")),
        FingerprintParts.link("alpha", FingerprintParts.region("a")),
      ],
    )

    let alpha = try #require(text.range(of: #""id":"alpha""#))
    let zeta = try #require(text.range(of: #""id":"zeta""#))

    #expect(alpha.lowerBound < zeta.lowerBound)
  }

  @Test
  func `content mode regions sort by digest and keep duplicates`() throws {
    let one = try FingerprintParts.region("one")
    let two = try FingerprintParts.region("two")

    let first = try fingerprint(implementation: [FingerprintParts.link("impl", one, two, one)])
    let second = try fingerprint(implementation: [FingerprintParts.link("impl", two, one, one)])
    let single = try fingerprint(implementation: [FingerprintParts.link("impl", one, two)])

    #expect(first == second)
    #expect(first != single)
  }

  @Test
  func `content mode ignores where a region sits`() throws {
    let here = try FingerprintParts.link("impl", FingerprintParts.region("x", file: "src/a.swift"))
    let there = try FingerprintParts.link(
      "impl",
      FingerprintParts.region("x", file: "src/b.swift", start: 40),
    )

    #expect(try fingerprint(implementation: [here]) == fingerprint(implementation: [there]))
  }

  @Test
  func `content-and-locator regions sort by file then start then end`() throws {
    let regions = try [
      FingerprintParts.region("x", file: "a.swift", start: 9),
      FingerprintParts.region("x", file: "b.swift", start: 0),
      FingerprintParts.region("x", file: "b.swift", start: 5),
    ]
    let ordered = try FingerprintParts.link(
      "impl",
      kind: .marker,
      regions[0],
      regions[1],
      regions[2],
    )
    let shuffled = try FingerprintParts.link(
      "impl",
      kind: .marker,
      regions[2],
      regions[0],
      regions[1],
    )

    let text = try payload(policy: strict, implementation: [shuffled])

    #expect(
      try fingerprint(policy: strict, implementation: [ordered])
        == fingerprint(policy: strict, implementation: [shuffled]),
    )
    #expect(text.contains(#""kind":"marker""#))
    #expect(text.contains(#""locator":{"end_byte":10,"file":"a.swift","start_byte":9}"#))
  }

  @Test
  func `content-and-locator mode notices a moved region and a different kind`() throws {
    let original = try fingerprint(
      policy: strict,
      implementation: [FingerprintParts.link("impl", FingerprintParts.region("x"))],
    )
    let moved = try fingerprint(
      policy: strict,
      implementation: [FingerprintParts.link("impl", FingerprintParts.region("x", start: 7))],
    )
    let marker = try fingerprint(
      policy: strict,
      implementation: [
        FingerprintParts.link("impl", kind: .marker, FingerprintParts.region("x")),
      ],
    )

    #expect(original != moved)
    #expect(original != marker)
  }

  @Test
  func `content mode ignores a binding's kind`() throws {
    let region = try FingerprintParts.region("x")
    let manual = try FingerprintParts.link("impl", kind: .manual, region)
    let transformer = try FingerprintParts.link("impl", kind: .transformer, region)

    #expect(try fingerprint(implementation: [manual]) == fingerprint(implementation: [transformer]))
  }

  @Test
  func `a binding id written twice in one collection is refused`() throws {
    let input = try FingerprintSamples.vectorA().replacing(
      contributions: RouteContributions(
        validation: [
          FingerprintParts.link("same", FingerprintParts.region("a")),
          FingerprintParts.link("same", FingerprintParts.region("b")),
        ],
      ),
    )

    #expect(throws: FingerprintingError.duplicateBinding("same")) {
      try fingerprinter.payload(of: input)
    }
  }

  @Test
  func `a binding with no region is refused`() throws {
    let input = try FingerprintSamples.vectorA().replacing(
      contributions: RouteContributions(validation: [FingerprintParts.link("empty")]),
    )

    #expect(throws: FingerprintingError.bindingWithoutRegions("empty")) {
      try fingerprinter.payload(of: input)
    }
  }

  @Test
  func `renaming a binding changes the fingerprint though the bytes are the same`() throws {
    let region = try FingerprintParts.region("x")

    let before = try fingerprint(implementation: [FingerprintParts.link("old", region)])
    let after = try fingerprint(implementation: [FingerprintParts.link("new", region)])

    #expect(before != after)
  }

  @Test
  func `resources sort by path and a file reached twice counts once`() throws {
    let users = try FingerprintParts.resource("fixtures/users.json", "{}")
    let config = try FingerprintParts.resource("config.json", "[]")

    let sorted = try fingerprint(resources: [config, users])
    let shuffled = try fingerprint(resources: [users, config, users])
    let single = try fingerprint(resources: [config])

    #expect(sorted == shuffled)
    #expect(sorted != single)
  }

  @Test
  func `one resource path with two contents is refused`() throws {
    let input = try FingerprintSamples.vectorA().replacing(
      contributions: RouteContributions(
        resources: [
          FingerprintParts.resource("a.json", "1"),
          FingerprintParts.resource("a.json", "2"),
        ],
      ),
    )

    #expect(throws: FingerprintingError.conflictingResource("a.json")) {
      try fingerprinter.payload(of: input)
    }
  }

  @Test
  func `paths in two Unicode forms stay two resources`() throws {
    let composed = try FingerprintParts.resource("caf\u{E9}.json", "{}")
    let decomposed = try FingerprintParts.resource("cafe\u{301}.json", "{}")

    let text = try payload(resources: [composed, decomposed])

    #expect(text.components(separatedBy: #""file":""#).count == 3)
    #expect(holds(text, "\"caf\u{E9}.json\""))
    #expect(holds(text, "\"cafe\u{301}.json\""))
  }
}

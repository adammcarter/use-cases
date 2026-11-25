@testable import UseCasesCore

/// Small pieces of route fingerprint input, built from text.
enum FingerprintParts {
  static func scenario(
    _ identifier: String,
    given: [String] = [],
  ) throws -> Scenario {
    try Scenario(
      identifier: ScenarioIdentifier(validating: identifier),
      given: given,
      when: ["Do it."],
      then: ["It is done."],
    )
  }

  static func identifiers(_ texts: [String]) throws -> [ScenarioIdentifier] {
    try texts.map { text in
      try ScenarioIdentifier(validating: text)
    }
  }

  /// The reference of text under the default policy.
  static func reference(_ text: String) -> ContentReference {
    FingerprintSamples.referencer.reference(of: Array(text.utf8))
  }

  /// A region holding `text` at `start` of `file`.
  static func region(
    _ text: String,
    file: String = "src/a.swift",
    start: Int = 0,
  ) throws -> LinkRegionContribution {
    try LinkRegionContribution(
      locator: FingerprintLocator(
        file: workspacePath(file),
        startByte: start,
        endByte: start + text.utf8.count,
      ),
      content: reference(text),
    )
  }

  /// A binding holding `regions`.
  static func link(
    _ binding: String,
    kind: LinkContributionKind = .manual,
    _ regions: LinkRegionContribution...,
  ) throws -> LinkContribution {
    try LinkContribution(
      binding: BindingIdentifier(validating: binding),
      kind: kind,
      regions: regions,
    )
  }

  /// A resource file holding `text`.
  static func resource(
    _ file: String,
    _ text: String,
  ) throws -> ResourceContribution {
    try ResourceContribution(
      file: workspacePath(file),
      content: reference(text),
    )
  }
}

extension FingerprintParts {
  /// A 64-character digest of zeros ending in `suffix`, to fix the order of two references.
  static func digest(ending suffix: String) -> String {
    String(repeating: "0", count: 64 - suffix.count) + suffix
  }

  /// A reference with a chosen digest and a length of 1.
  static func reference(digestEnding suffix: String) -> ContentReference {
    ContentReference(
      byteLength: 1,
      digest: digest(ending: suffix),
    )
  }

  /// The canonical text of a reference of length 1, as the payload writes it.
  static func written(digestEnding suffix: String) -> String {
    let head = #"{"algorithm":"sha256","byte_length":1,"digest":""#
    let hex = digest(ending: suffix)

    return head + hex + #""}"#
  }

  /// A region at `file` from `start` to `start + 1`, holding the reference ending in `suffix`.
  static func region(
    file: String,
    start: Int,
    digestEnding suffix: String = "aa",
  ) throws -> LinkRegionContribution {
    try LinkRegionContribution(
      locator: FingerprintLocator(
        file: workspacePath(file),
        startByte: start,
        endByte: start + 1,
      ),
      content: reference(digestEnding: suffix),
    )
  }
}

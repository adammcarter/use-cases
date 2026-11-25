@testable import UseCasesCore

extension RunIdentifier {
  /// The run id for a small number.
  static func sample(_ number: Int) -> RunIdentifier {
    guard let identifier = try? RunIdentifier(validating: StoreFixture.identifier(number)) else {
      preconditionFailure("\(number) is not a run id")
    }

    return identifier
  }
}

extension UseCaseIdentifier {
  static func sample(_ text: String) -> UseCaseIdentifier {
    guard let identifier = try? UseCaseIdentifier(validating: text) else {
      preconditionFailure("\(text) is not a use case id")
    }

    return identifier
  }
}

extension RouteIdentifier {
  static func sample(_ text: String) -> RouteIdentifier {
    guard let identifier = try? RouteIdentifier(validating: text) else {
      preconditionFailure("\(text) is not a route id")
    }

    return identifier
  }
}

extension RouteFingerprint {
  /// A version 1 fingerprint whose digest is this hex digit repeated.
  static func sample(_ digit: Character) -> RouteFingerprint {
    sample(text: "uc-route-v1-sha256:" + String(repeating: digit, count: 64))
  }

  static func sample(text: String) -> RouteFingerprint {
    guard let fingerprint = try? RouteFingerprint(validating: text) else {
      preconditionFailure("\(text) is not a fingerprint")
    }

    return fingerprint
  }
}

extension RunDiagnostic {
  static func sample(
    _ problem: String,
    _ useCase: UseCaseIdentifier,
    _ route: RouteIdentifier,
    _ fingerprint: RouteFingerprint,
  ) -> RunDiagnostic {
    RunDiagnostic(
      problem: problem,
      useCase: useCase,
      route: route,
      fingerprint: fingerprint,
      files: [],
      links: [],
    )
  }
}

extension StoredRun {
  /// A sealed run holding these results; `diagnostics: nil` is a run read through its envelope.
  static func sample(
    _ number: Int,
    _ results: [StoredResult],
    diagnostics: [RunDiagnostic]? = [],
  ) -> StoredRun {
    let identifier = RunIdentifier.sample(number)
    let digest = StoreSamples.digest("0")
    let manifest = diagnostics.map {
      RunManifest(
        identifier: identifier,
        createdAt: StoreSamples.timestamp,
        kind: .record,
        sources: [],
        errors: [],
        diagnostics: $0,
        unlinkedTests: [],
        notes: [],
      )
    }

    return StoredRun(
      identifier: identifier,
      completion: RunCompletion(
        version: 1,
        identifier: identifier,
        resultCount: results.count,
        manifestDigest: digest,
        resultsDigest: digest,
        details: nil,
      ),
      manifest: manifest,
      results: results,
      findings: [],
    )
  }
}

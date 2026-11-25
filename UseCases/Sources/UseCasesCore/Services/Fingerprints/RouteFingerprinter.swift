struct RouteFingerprinter: RouteFingerprinting {
  private let encoder: any CanonicalJSONEncoding
  private let digester: any FingerprintDigesting

  init(
    encoder: any CanonicalJSONEncoding,
    digester: any FingerprintDigesting,
  ) {
    self.encoder = encoder
    self.digester = digester
  }

  init() {
    self.init(
      encoder: CanonicalJSONEncoder(),
      digester: FingerprintDigester(),
    )
  }

  func payload(of input: RouteFingerprintInput) throws(FingerprintingError) -> [UInt8] {
    let value = try value(of: input)

    do {
      return try encoder.encode(value)
    } catch {
      throw .encoding(error)
    }
  }

  func fingerprint(of input: RouteFingerprintInput) throws(FingerprintingError) -> String {
    let digest = try digester.digest(
      of: payload(of: input),
      in: .route,
    )

    return (FingerprintDomain.route.externalPrefix ?? "") + digest
  }

  private func value(
    of input: RouteFingerprintInput,
  ) throws(FingerprintingError) -> CanonicalValue {
    guard let intent = input.intent else {
      throw .missingIntent
    }

    let scenarios = try scenariosValue(
      of: input.scenarios,
      covers: input.covers,
    )
    let implementation = try linksValue(
      of: input.implementationLinks,
      policy: input.policy,
    )
    let validation = try linksValue(
      of: input.validationLinks,
      policy: input.policy,
    )
    let resources = try resourcesValue(of: input.resources)

    return .members([
      "fingerprint_version": .integer(1),
      "freshness_policy": policyValue(of: input.policy),
      "use_case_id": .string(input.useCase.text),
      "route_id": .string(input.route.text),
      "intent": .string(intent),
      "covered_scenarios": scenarios,
      "route": routeValue(of: input),
      "implementation_links": implementation,
      "validation_links": validation,
      "resources": resources,
    ])
  }
}

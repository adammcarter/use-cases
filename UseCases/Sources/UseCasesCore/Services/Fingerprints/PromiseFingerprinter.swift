struct PromiseFingerprinter: PromiseFingerprinting {
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

  func payload(of input: PromiseFingerprintInput) throws(FingerprintingError) -> [UInt8] {
    do {
      return try encoder.encode(value(of: input))
    } catch {
      throw .encoding(error)
    }
  }

  func fingerprint(of input: PromiseFingerprintInput) throws(FingerprintingError) -> String {
    try digester.digest(
      of: payload(of: input),
      in: .promise,
    )
  }

  /// All seven members are written: absent text is null, an absent list is empty.
  private func value(of input: PromiseFingerprintInput) -> CanonicalValue {
    .members([
      "id": .string(input.useCase.text),
      "title": .string(input.title),
      "description": text(input.description),
      "value_tier": text(input.valueTier?.rawValue),
      "intent": text(input.intent),
      "scenarios": .array(
        input.scenarios.map { scenario in
          scenario.canonical
        },
      ),
      "out_of_scope": .strings(input.outOfScope),
    ])
  }

  private func text(_ text: String?) -> CanonicalValue {
    guard let text else {
      return .null
    }

    return .string(text)
  }
}

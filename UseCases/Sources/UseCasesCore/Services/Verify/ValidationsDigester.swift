/// Digests validations as canonical JSON: members sorted by key, no white space.
struct ValidationsDigester: ValidationsDigesting {
  private let printer: any StoreJSONWriting
  private let hasher: any Hashing

  init(
    printer: any StoreJSONWriting = StoreJSONWriter(),
    hasher: any Hashing = SHA256Hasher(),
  ) {
    self.printer = printer
    self.hasher = hasher
  }

  func digest(of validations: [BridgeValidation]) -> String {
    hasher.sha256Hex(
      of: printer.compact(.array(validations.map(Self.document))),
    )
  }

  private static func document(of validation: BridgeValidation) -> StoreJSONValue {
    .present([
      "id": .string(validation.identifier.text),
      "report": validation.report.map(StoreJSONValue.string),
      "run": validation.run.map(StoreJSONValue.strings),
      "working_dir": validation.workingDirectory.map(\.text).map(StoreJSONValue.string),
      "transformer": .string(validation.transformer.name),
      "settings": validation.settings.map(StoreJSONValue.init),
      "timeout_seconds": validation.timeoutSeconds.map(StoreJSONValue.integer),
    ])
  }
}

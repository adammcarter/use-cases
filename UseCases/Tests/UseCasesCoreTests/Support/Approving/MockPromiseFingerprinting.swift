@testable import UseCasesCore

/// A fingerprinter that answers what the test decides, or fails.
struct MockPromiseFingerprinting: PromiseFingerprinting {
  private let outcome: Result<String, FingerprintingError>

  init(answering fingerprint: String) {
    outcome = .success(fingerprint)
  }

  init(failing error: FingerprintingError) {
    outcome = .failure(error)
  }

  func payload(of _: PromiseFingerprintInput) throws(FingerprintingError) -> [UInt8] {
    []
  }

  func fingerprint(of _: PromiseFingerprintInput) throws(FingerprintingError) -> String {
    try outcome.get()
  }
}

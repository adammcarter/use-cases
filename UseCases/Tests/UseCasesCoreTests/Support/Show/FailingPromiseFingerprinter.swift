@testable import UseCasesCore

/// A fingerprinter that cannot fingerprint anything.
struct FailingPromiseFingerprinter: PromiseFingerprinting {
  func payload(of _: PromiseFingerprintInput) throws(FingerprintingError) -> [UInt8] {
    throw .missingIntent
  }

  func fingerprint(of _: PromiseFingerprintInput) throws(FingerprintingError) -> String {
    throw .missingIntent
  }
}

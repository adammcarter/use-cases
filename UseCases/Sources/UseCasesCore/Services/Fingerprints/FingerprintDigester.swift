struct FingerprintDigester: FingerprintDigesting {
  private let hasher: any Hashing

  init(hasher: any Hashing) {
    self.hasher = hasher
  }

  /// Hashes with SHA-256.
  init() {
    self.init(hasher: SHA256Hasher())
  }

  func digest(
    of payload: [UInt8],
    in domain: FingerprintDomain,
  ) -> String {
    hasher.sha256Hex(
      of: framed(
        payload,
        in: domain,
      ),
    )
  }

  func accumulator(
    in domain: FingerprintDomain,
    payloadLength length: Int,
  ) -> any DigestAccumulating {
    var accumulator = hasher.accumulator()

    accumulator.add(header(of: domain, payloadLength: length))

    return accumulator
  }

  /// The bytes that are hashed in front of a payload.
  private func header(
    of domain: FingerprintDomain,
    payloadLength length: Int,
  ) -> [UInt8] {
    var bytes = Array(domain.name.utf8)

    bytes.append(0x00)
    bytes.append(contentsOf: Array(String(length).utf8))
    bytes.append(UInt8(ascii: ":"))

    return bytes
  }

  /// The exact bytes that are hashed.
  func framed(
    _ payload: [UInt8],
    in domain: FingerprintDomain,
  ) -> [UInt8] {
    header(of: domain, payloadLength: payload.count) + payload
  }
}

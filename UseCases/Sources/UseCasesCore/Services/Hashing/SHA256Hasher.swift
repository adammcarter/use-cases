/// SHA-256 from swift-crypto: CryptoKit on Apple platforms, BoringSSL on Linux, one answer on both.
struct SHA256Hasher: Hashing {
  func sha256Hex(of bytes: [UInt8]) -> String {
    var accumulator = SHA256Accumulator()
    accumulator.add(bytes)

    return accumulator.hex()
  }

  func accumulator() -> any DigestAccumulating {
    SHA256Accumulator()
  }
}

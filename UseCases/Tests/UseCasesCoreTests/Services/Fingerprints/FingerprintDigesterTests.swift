import Testing
@testable import UseCasesCore

struct FingerprintDigesterTests {
  struct Row: CustomTestStringConvertible {
    let domain: FingerprintDomain
    let payload: String
    let digest: String

    var testDescription: String {
      "\(domain.name) \(payload.isEmpty ? "empty" : payload)"
    }
  }

  private static let rows = [
    Row(
      domain: .content,
      payload: "",
      digest: "e0de6ec0d583e251562c017f7084f22e1007c0f60276e00d18811909e976d4f5",
    ),
    Row(
      domain: .content,
      payload: "abc",
      digest: "efb223658e20ee620f5c7f42edb1f1146cda800481df6206f80e86ac400dd989",
    ),
    Row(
      domain: .content,
      payload: "{}",
      digest: "52a8074184635b0d84a433bb77f017db964adf886297b3eb1604d8b0de24bdf8",
    ),
    Row(
      domain: .workspace,
      payload: "{}",
      digest: "9b1a9c046021c571b4e67572309c0bcdcb37fa3778a8143105ea2b5a7d49d7e7",
    ),
  ]

  @Test(arguments: rows)
  func `the framing table of the chapter hashes to its published digests`(row: Row) {
    let digest = FingerprintDigester().digest(
      of: Array(row.payload.utf8),
      in: row.domain,
    )

    #expect(digest == row.digest)
  }

  @Test
  func `the framed bytes are domain, zero byte, decimal length, colon and payload`() {
    let framed = FingerprintDigester().framed(
      Array("abc".utf8),
      in: .content,
    )

    #expect(framed == Array("use-cases/content/v1".utf8) + [0x00] + Array("3:abc".utf8))
  }

  @Test
  func `a long payload has its length written without leading zeros`() {
    let framed = FingerprintDigester().framed(
      [UInt8](repeating: 0x61, count: 1000),
      in: .route,
    )

    #expect(framed.starts(with: Array("use-cases/route/v1".utf8) + [0x00] + Array("1000:".utf8)))
    #expect(framed.count == "use-cases/route/v1".utf8.count + 1 + "1000:".utf8.count + 1000)
  }

  @Test
  func `the same payload in two domains has two digests`() {
    let digester = FingerprintDigester()
    let payload = Array("{}".utf8)

    let digests = Set(
      FingerprintDomain.allCases.map { domain in
        digester.digest(
          of: payload,
          in: domain,
        )
      },
    )

    #expect(digests.count == FingerprintDomain.allCases.count)
  }

  @Test
  func `a digest is 64 lowercase hexadecimal characters`() {
    let digest = FingerprintDigester().digest(
      of: [],
      in: .promise,
    )

    #expect(digest.count == 64)
    #expect(digest.allSatisfy { character in "0123456789abcdef".contains(character) })
  }
}

import Foundation
import Testing
@testable import UseCasesCore

/// `use-cases keygen`'s keypair. The values are random by design, so what is pinned
/// is the SHAPE node's own output has, and that the halves work — here and in
/// node.
struct SigningKeyGenerationTests {
  /// Each PEM line, with base64 body lines reduced to their length, exactly as
  /// the corpus records node's.
  private func shape(_ pem: String) -> [String] {
    let lines = pem.components(separatedBy: "\n")
    return lines.enumerated().map { index, line in
      index == 0 || index == lines.count - 2 || line.isEmpty ? line : "<base64:\(line.count)>"
    }
  }

  /// The DER under a single-line PEM body.
  private func body(of pem: String) -> Data? {
    let lines = pem.components(separatedBy: "\n")
    return lines.count > 1 ? Data(base64Encoded: lines[1]) : nil
  }

  @Test
  func `a generated keypair has the shape node's has`() throws {
    let expected = try #require(MarkersLedgerFixtures.root()["keygen_shape"])
    let keypair = SigningKeyGeneration.generate()

    #expect(try shape(keypair.privatePEM) == MarkersLedgerFixtures.strings(
      expected,
      "private_pem_lines",
    ))
    #expect(try shape(keypair.publicPEM) == MarkersLedgerFixtures.strings(
      expected,
      "public_pem_lines",
    ))

    let privateBody = try #require(body(of: keypair.privatePEM))
    let publicBody = try #require(body(of: keypair.publicPEM))
    #expect(try [UInt8](privateBody.prefix(16)).hexadecimal
      == MarkersLedgerFixtures.string(expected, "private_der_prefix_hex"))
    #expect(try [UInt8](publicBody.prefix(12)).hexadecimal
      == MarkersLedgerFixtures.string(expected, "public_der_prefix_hex"))
  }

  @Test
  func `each call returns a distinct keypair`() {
    let first = SigningKeyGeneration.generate()
    let second = SigningKeyGeneration.generate()

    #expect(first.privatePEM != second.privatePEM)
    #expect(first.publicPEM != second.publicPEM)
  }

  @Test
  func `the private half signs what the public half verifies`() throws {
    let keypair = SigningKeyGeneration.generate()
    let event = JSONObject([("event_id", .string("evt_keygen"))])

    let signed = try ProofSignature.sign(
      event,
      privateKeyPEM: keypair.privatePEM,
      keyIdentifier: "k",
    )

    #expect(try ProofSignature.verify(.object(signed), resolver: { _, _ in keypair.publicPEM })
      == .verified(keyIdentifier: "k"))
    let other = SigningKeyGeneration.generate()
    #expect(try ProofSignature.verify(.object(signed), resolver: { _, _ in other.publicPEM })
      != .verified(keyIdentifier: "k"))
  }

  @Test
  func `node imports a generated keypair and each side verifies the other's signature`() throws {
    let keypair = SigningKeyGeneration.generate()
    let event = JSONObject([("event_id", .string("evt_keygen_node"))])
    let signed = try ProofSignature.sign(
      event,
      privateKeyPEM: keypair.privatePEM,
      keyIdentifier: "k",
    )
    let payload = try ProofSignature.signingPayload(signed)

    let verdicts = try NodeCrossCheck.run([NodeCrossCheck.Case(
      payload: payload,
      signature: #require(signed["signature"]?["value"]?.stringValue),
      publicKeyPEM: keypair.publicPEM,
      privateKeyPEM: keypair.privatePEM,
    )])

    let verdict = try #require(verdicts.first)
    #expect(verdict.nodeVerifiedSwiftSignature)
    var nodeSigned = signed
    nodeSigned["signature"] = .object(JSONObject([
      ("alg", .string("ed25519")),
      ("key_id", .string("k")),
      ("value", .string(verdict.nodeSignature)),
    ]))
    #expect(try ProofSignature.verify(.object(nodeSigned), resolver: { _, _ in keypair.publicPEM })
      == .verified(keyIdentifier: "k"))
  }
}

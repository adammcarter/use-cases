import Foundation
import Testing
@testable import UseCasesCore

/// ed25519 proof signatures (spec 5.2/5.3). The payload is the code-unit
/// canonical JSON of the event without its signature, and a signature made by
/// either implementation must verify in the other.
struct ProofSignatureTests {
  @Test(arguments: MarkersLedgerGoldenCorpus.proofSignatureCaseNames)
  func `verifying a node-signed event agrees with the TypeScript`(caseName: String) throws {
    let entry = try MarkersLedgerFixtures.entry(caseName, in: "proof_signature")
    let event = try MarkersLedgerFixtures.parsed(entry, "event_text")
    let resolver = try MarkersLedgerFixtures.resolver(#require(entry["resolver"]))
    let expected = try #require(entry["verify"])

    let result = try ProofSignature.verify(event, resolver: resolver)

    #expect(MarkersLedgerFixtures.wire(result.jsonValue) == MarkersLedgerFixtures.wire(expected))
    let payload = try #require(event.objectValue)
    #expect(try ProofSignature.signingPayload(payload) == entry["payload"]?["value"]?.stringValue)
  }

  /// CryptoKit signs with fresh randomness, so the signature bytes differ from
  /// node's deterministic ones; everything else about the signed event must
  /// not, and both signatures must verify.
  @Test(arguments: MarkersLedgerGoldenCorpus.signingCaseNames)
  func `signing produces the TypeScript's signed event`(caseName: String) throws {
    let entry = try MarkersLedgerFixtures.entry(caseName, in: "signing")
    let event = try #require(MarkersLedgerFixtures.parsed(entry, "event_text").objectValue)
    let privateKey = try MarkersLedgerFixtures.pem("primary", "private_pem")
    let publicKey = try MarkersLedgerFixtures.pem("primary", "public_pem")
    let nodeSigned = try JSONParser.parse(MarkersLedgerFixtures.string(entry, "signed_wire"))

    let signed = try ProofSignature.sign(
      event,
      privateKeyPEM: privateKey,
      keyIdentifier: "ci-key-1",
    )

    #expect(try ProofSignature.signingPayload(event) == MarkersLedgerFixtures.string(
      entry,
      "payload",
    ))
    #expect(withoutSignatureValue(.object(signed)) == withoutSignatureValue(nodeSigned))
    #expect(try ProofSignature.verify(.object(signed), resolver: { _, _ in publicKey })
      == .verified(keyIdentifier: "ci-key-1"))
    #expect(try ProofSignature.verify(nodeSigned, resolver: { _, _ in publicKey })
      == .verified(keyIdentifier: "ci-key-1"))
  }

  private func withoutSignatureValue(_ value: JSONValue) -> String {
    guard var object = value.objectValue, var signature = object["signature"]?.objectValue else {
      return MarkersLedgerFixtures.wire(value)
    }
    signature["value"] = .string("<signature>")
    object["signature"] = .object(signature)
    return MarkersLedgerFixtures.wire(.object(object))
  }

  @Test
  func `a Swift signature verifies in node, and node's over the same payload verifies here`()
    throws
  {
    let privateKey = try MarkersLedgerFixtures.pem("primary", "private_pem")
    let publicKey = try MarkersLedgerFixtures.pem("primary", "public_pem")
    var cases: [NodeCrossCheck.Case] = []
    for entry in try MarkersLedgerFixtures.section("signing") {
      let event = try #require(MarkersLedgerFixtures.parsed(entry, "event_text").objectValue)
      let signed = try ProofSignature.sign(event, privateKeyPEM: privateKey, keyIdentifier: "k")
      let value = try #require(signed["signature"]?["value"]?.stringValue)
      try cases.append(NodeCrossCheck.Case(
        payload: ProofSignature.signingPayload(signed),
        signature: value,
        publicKeyPEM: publicKey,
        privateKeyPEM: privateKey,
      ))
    }

    let verdicts = try NodeCrossCheck.run(cases)

    #expect(verdicts.count == cases.count)
    for (verdict, check) in zip(verdicts, cases) {
      #expect(verdict.nodeVerifiedSwiftSignature)
      var event = try #require(JSONParser.parse(check.payload).objectValue)
      event["signature"] = .object(JSONObject([
        ("alg", .string("ed25519")),
        ("key_id", .string("k")),
        ("value", .string(verdict.nodeSignature)),
      ]))
      #expect(try ProofSignature.verify(.object(event), resolver: { _, _ in publicKey })
        == .verified(keyIdentifier: "k"))
    }
  }

  @Test
  func `node's lenient base64 decoding is reproduced`() throws {
    for entry in try MarkersLedgerFixtures.section("base64_decode") {
      let input = try MarkersLedgerFixtures.string(entry, "input")

      #expect(
        try NodeBuffer.base64Decode(input).hexadecimal == MarkersLedgerFixtures.string(
          entry,
          "hex",
        ),
        "\(entry["name"]?.stringValue ?? "")",
      )
    }
  }

  @Test
  func `node's lenient hex decoding is reproduced`() throws {
    for entry in try MarkersLedgerFixtures.section("hex_decode") {
      let input = try MarkersLedgerFixtures.string(entry, "input")

      #expect(
        try NodeBuffer.hexDecode(input).hexadecimal == MarkersLedgerFixtures.string(entry, "hex"),
        "\(entry["name"]?.stringValue ?? "")",
      )
    }
  }

  @Test
  func `signing with something that is not a private key is refused`() throws {
    let publicKey = try MarkersLedgerFixtures.pem("primary", "public_pem")

    #expect(throws: ProofSignatureError.invalidPrivateKey) {
      try ProofSignature.sign(JSONObject(), privateKeyPEM: publicKey, keyIdentifier: "k")
    }
    #expect(ProofSignatureError.invalidPrivateKey.code == "invalid_private_key")
  }

  @Test
  func `a null event cannot be read, exactly as the TypeScript throws`() {
    let error = #expect(throws: ProofSignatureError.self) {
      try ProofSignature.verify(.null, resolver: { _, _ in nil })
    }
    #expect(error?.message == "Cannot read properties of null (reading 'signature')")
  }

  @Test
  func `the signature failure codes are frozen`() {
    #expect(SignatureFailureCode.allCases.map(\.rawValue) == [
      "SIGNATURE_MISSING", "SIGNATURE_ALG_UNSUPPORTED", "UNKNOWN_KEY_ID", "BAD_SIGNATURE",
    ])
  }
}

extension [UInt8] {
  var hexadecimal: String {
    map { byte in
      String(format: "%02x", byte)
    }
    .joined()
  }
}

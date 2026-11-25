import Testing
@testable import UseCasesCore

/// The conformance vectors of chapter 11 §89.8: the published payload bytes and fingerprints,
/// reproduced from the real pieces (the marker scanner, the content referencer, the encoder).
struct RouteFingerprinterVectorTests {
  struct Vector: CustomTestStringConvertible, Sendable {
    let name: String
    let input: @Sendable () throws -> RouteFingerprintInput
    let payload: String
    let fingerprint: String
    let size: Int

    var testDescription: String {
      "vector \(name)"
    }
  }

  private static let vectors = [
    Vector(
      name: "A",
      input: FingerprintSamples.vectorA,
      payload: VectorExpectations.payloadA,
      fingerprint: VectorExpectations.fingerprintA,
      size: 552,
    ),
    Vector(
      name: "B",
      input: FingerprintSamples.vectorB,
      payload: VectorExpectations.payloadB,
      fingerprint: VectorExpectations.fingerprintB,
      size: 927,
    ),
    Vector(
      name: "C",
      input: FingerprintSamples.vectorC,
      payload: VectorExpectations.payloadC,
      fingerprint: VectorExpectations.fingerprintC,
      size: 1131,
    ),
    Vector(
      name: "D",
      input: FingerprintSamples.vectorD,
      payload: VectorExpectations.payloadD,
      fingerprint: VectorExpectations.fingerprintD,
      size: 928,
    ),
    Vector(
      name: "E",
      input: FingerprintSamples.vectorE,
      payload: VectorExpectations.payloadE,
      fingerprint: VectorExpectations.fingerprintE,
      size: 1132,
    ),
  ]

  @Test(arguments: vectors)
  func `the payload is the published bytes`(vector: Vector) throws {
    let payload = try RouteFingerprinter().payload(of: vector.input())

    #expect(payload.count == vector.size)
    #expect(payload.utf8Text == vector.payload)
  }

  @Test(arguments: vectors)
  func `the fingerprint is the published one`(vector: Vector) throws {
    let fingerprint = try RouteFingerprinter().fingerprint(of: vector.input())

    #expect(fingerprint == vector.fingerprint)
  }

  @Test
  func `binding identity alone changes every fingerprint`() throws {
    let content = try RouteFingerprinter().fingerprint(of: FingerprintSamples.vectorB())
    let locator = try RouteFingerprinter().fingerprint(of: FingerprintSamples.vectorC())

    #expect(content != locator)
  }

  @Test
  func `a nested same-line pair leaves its tokens out but keeps the syntax around them`() throws {
    let input = try FingerprintSamples.vectorD()
    let region = try #require(input.validationLinks.first?.regions.first)

    #expect(region.content.byteLength == 31)
  }

  @Test
  func `line mode nested sentinel lines are in the locator but not the content`() throws {
    let input = try FingerprintSamples.vectorE()
    let region = try #require(input.validationLinks.first?.regions.first)

    #expect(region.locator.startByte == 48)
    #expect(region.locator.endByte == 126)
    #expect(region.content.byteLength == 8)
  }
}

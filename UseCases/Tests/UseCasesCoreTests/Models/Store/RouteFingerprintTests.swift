import Testing
@testable import UseCasesCore

struct RouteFingerprintTests {
  static let digest = String(repeating: "a", count: 64)

  @Test(arguments: [
    "uc-route-v1-sha256:" + digest,
    "uc-route-v2-blake3:abc",
    "uc-route-v10-x-y:\u{E9}",
    "uc-route-v1-sha512:anything",
  ])
  func `a versioned representation is a fingerprint`(text: String) throws {
    #expect(try RouteFingerprint(validating: text).text == text)
  }

  @Test(arguments: [
    "",
    "sha256:x",
    "uc-route-v0-sha256:abc",
    "uc-route-v01-sha256:abc",
    "uc-route-v-sha256:abc",
    "uc-route-v1-:abc",
    "uc-route-v1sha256:abc",
    "uc-route-v1-SHA256:abc",
    "uc-route-v1-sha256",
    "UC-ROUTE-v1-sha256:abc",
  ])
  func `text that is not versioned is refused`(text: String) {
    #expect(throws: RouteFingerprintError.notVersioned(text)) {
      try RouteFingerprint(validating: text)
    }
  }

  @Test(arguments: [
    "uc-route-v1-sha256:",
    "uc-route-v1-sha256:abc",
    "uc-route-v1-sha256:" + String(repeating: "A", count: 64),
    "uc-route-v1-sha256:" + String(repeating: "a", count: 65),
    "uc-route-v1-sha256:" + String(repeating: "g", count: 64),
    "uc-route-v2-blake3:",
    "uc-route-v2-blake3:a:b",
    "uc-route-v2-blake3:a b",
    "uc-route-v2-blake3:a\n",
    "uc-route-v2-blake3:a\u{A0}b",
    "uc-route-v2-blake3:a\u{FEFF}",
  ])
  func `a malformed value is refused`(text: String) {
    #expect(throws: RouteFingerprintError.malformedValue(text)) {
      try RouteFingerprint(validating: text)
    }
  }

  @Test
  func `a value may hold the control character and the next line that ECMA white space does not`(
  ) throws {
    #expect(try RouteFingerprint(validating: "uc-route-v2-x:a\u{85}b")
      .text == "uc-route-v2-x:a\u{85}b")
  }

  @Test
  func `equal only when the scalars are`() throws {
    let composed = try RouteFingerprint(validating: "uc-route-v2-x:\u{E9}")
    let decomposed = try RouteFingerprint(validating: "uc-route-v2-x:e\u{301}")

    #expect(composed != decomposed)
    #expect(Set([composed, decomposed]).count == 2)
  }
}

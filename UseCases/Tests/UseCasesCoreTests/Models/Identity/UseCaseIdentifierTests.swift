import Testing
@testable import UseCasesCore

struct UseCaseIdentifierTests {
  @Test(
    arguments: [
      "success", "app.auth.login.success", "shop.payments.card.refund", "a.b", "v2.3d.ipv6",
    ],
  )
  func `a full id on the namespace grammar is accepted`(text: String) throws {
    let identifier = try UseCaseIdentifier(validating: text)

    #expect(identifier.text == text)
    #expect(identifier.description == text)
  }

  @Test(
    arguments: [
      ("", IdentityError.empty),
      ("app..login", .emptySegment(within: "app..login")),
      ("App.login", .invalidCharacter("A", within: "App.login")),
      ("app.login#unit-tests", .invalidCharacter("#", within: "app.login#unit-tests")),
      ("app.login\n", .invalidCharacter("\n", within: "app.login\n")),
    ],
  )
  func `a full id off the grammar is refused`(
    text: String,
    expected: IdentityError,
  ) {
    #expect(throws: expected) {
      try UseCaseIdentifier(validating: text)
    }
  }

  @Test(arguments: Composition.all)
  func `scope prefixes, the file prefix and the local id compose in that order`(
    composition: Composition,
  ) throws {
    var scopePrefixes: [Namespace] = []
    for text in composition.scopePrefixes {
      try scopePrefixes.append(Namespace(validating: text))
    }

    var filePrefix: Namespace?
    if let text = composition.filePrefix {
      filePrefix = try Namespace(validating: text)
    }

    let identifier = try UseCaseIdentifier(
      scopePrefixes: scopePrefixes,
      filePrefix: filePrefix,
      localIdentifier: IdentifierSegment(validating: composition.localIdentifier),
    )

    #expect(identifier.text == composition.expected)
  }

  @Test
  func `a composed id equals the same id written out`() throws {
    let composed = try UseCaseIdentifier(
      scopePrefixes: [Namespace(validating: "app"), Namespace(validating: "auth")],
      filePrefix: Namespace(validating: "login"),
      localIdentifier: IdentifierSegment(validating: "success"),
    )
    let written = try UseCaseIdentifier(validating: "app.auth.login.success")

    #expect(composed == written)
    #expect(Set([composed, written]).count == 1)
  }
}

extension UseCaseIdentifierTests {
  struct Composition: Sendable, CustomTestStringConvertible {
    static let all = [
      Composition(
        scopePrefixes: [],
        filePrefix: nil,
        localIdentifier: "success",
        expected: "success",
      ),
      Composition(
        scopePrefixes: ["app"],
        filePrefix: nil,
        localIdentifier: "success",
        expected: "app.success",
      ),
      Composition(
        scopePrefixes: [],
        filePrefix: "login",
        localIdentifier: "success",
        expected: "login.success",
      ),
      Composition(
        scopePrefixes: ["app"],
        filePrefix: "login",
        localIdentifier: "success",
        expected: "app.login.success",
      ),
      Composition(
        scopePrefixes: ["app", "auth"],
        filePrefix: "login",
        localIdentifier: "success",
        expected: "app.auth.login.success",
      ),
      Composition(
        scopePrefixes: ["shop", "payments.card"],
        filePrefix: "refund",
        localIdentifier: "partial",
        expected: "shop.payments.card.refund.partial",
      ),
      Composition(
        scopePrefixes: ["a.b", "c.d", "e.f"],
        filePrefix: "g.h",
        localIdentifier: "i",
        expected: "a.b.c.d.e.f.g.h.i",
      ),
    ]

    let scopePrefixes: [String]
    let filePrefix: String?
    let localIdentifier: String
    let expected: String

    var testDescription: String {
      expected
    }
  }
}

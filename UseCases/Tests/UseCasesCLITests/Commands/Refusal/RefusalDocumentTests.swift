import Foundation
import Testing
@testable import UseCasesCLI

struct RefusalDocumentTests {
  private func object(_ document: RefusalDocument) throws -> [String: Any] {
    let text = try document.jsonText()
    let value = try JSONSerialization.jsonObject(with: Data(text.utf8))

    return try #require(value as? [String: Any])
  }

  @Test
  func `a refusal holds the version, the command and the error, and nothing else`() throws {
    let found = try object(
      RefusalDocument(
        command: "validate",
        kind: .invalid,
        message: "use-cases/a.yml:3: bad",
      ),
    )
    let error = try #require(found["error"] as? [String: String])

    #expect(Set(found.keys) == ["output_version", "command", "error"])
    #expect(found["output_version"] as? Int == 1)
    #expect(found["command"] as? String == "validate")
    #expect(error == ["kind": "invalid", "message": "use-cases/a.yml:3: bad"])
  }

  @Test
  func `a command line that names no command has a null command, not a missing one`() throws {
    let found = try object(
      RefusalDocument(
        command: nil,
        kind: .usage,
        message: "Unknown option",
      ),
    )

    #expect(found.keys.contains("command"))
    #expect(found["command"] is NSNull)
  }

  @Test
  func `slashes are written as they are, so a path reads as a path`() throws {
    let text = try RefusalDocument(
      command: "validate",
      kind: .invalid,
      message: "use-cases/a.yml: bad",
    ).jsonText()

    #expect(text.contains("use-cases/a.yml: bad"))
  }

  @Test(arguments: [
    (RefusalKind.usage, "usage"),
    (RefusalKind.invalid, "invalid"),
    (RefusalKind.refused, "refused"),
    (RefusalKind.storage, "storage"),
    (RefusalKind.cancelled, "cancelled"),
  ])
  func `each kind is written under its published name`(
    kind: RefusalKind,
    name: String,
  ) {
    #expect(kind.rawValue == name)
  }
}

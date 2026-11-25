import Foundation
import Testing
@testable import UseCasesCore

struct IntentRendererTests {
  private func intent(_ json: String) throws -> IntentLayout {
    try IntentRenderer(
      reader: MockAuthoredInput(AuthoredInput(name: "stdin", value: authored(json))),
    ).intent(readingFrom: "-")
  }

  private func refusal(of json: String) throws -> LayoutRenderingError? {
    do {
      _ = try intent(json)

      return nil
    } catch let error as LayoutRenderingError {
      return error
    }
  }

  @Test
  func `an intent is what, why and who`() throws {
    let found = try intent(
      #"{"what": " Refund part ", "why": "Customers return", "who": [" staff ", "customers"]}"#,
    )

    #expect(found == IntentLayout(
      what: "Refund part",
      why: "Customers return",
      who: ["staff", "customers"],
    ))
  }

  @Test
  func `who may be left out, and the model still has none`() throws {
    #expect(try intent(#"{"what": "x", "why": "y"}"#).who.isEmpty)
    #expect(try intent(#"{"what": "x", "why": "y", "who": []}"#).who.isEmpty)
  }

  @Test(arguments: [
    #"{"what": "x"}"#,
    #"{"why": "y"}"#,
    #"{"what": "", "why": "y"}"#,
    #"{"what": "x", "why": " \n "}"#,
    #"{"what": 1, "why": "y"}"#,
    #"{"what": "x", "why": "y", "who": "staff"}"#,
    #"{"what": "x", "why": "y", "who": [1]}"#,
    #"{"what": "x", "why": "y", "who": [""]}"#,
    #"{"what": "x", "why": "y", "when": "now"}"#,
    #"["what"]"#,
    "7",
  ])
  func `anything else is not an intent`(json: String) throws {
    let refused = try #require(try refusal(of: json))

    #expect(refused == .invalidIntent(name: "stdin"))
    #expect(refused.kind == .usage)
    #expect(refused.message.contains("an intent has `what` and `why`"))
  }

  @Test(arguments: [
    ("\u{1B}[8m", "\\x1B"),
    ("\u{7F}", "\\x7F"),
    ("\u{9B}", "\\x9B"),
    ("\u{202E}", "\\u202E"),
    ("\u{2067}", "\\u2067"),
  ])
  func `a control character in the intent is refused, naming the field`(
    control: String,
    spelled: String,
  ) throws {
    for field in ["what", "why", "who"] {
      let text = "a\(control)b"
      var object: [String: Any] = ["what": "x", "why": "y", "who": ["z"]]
      object[field] = field == "who" ? [text] : text
      let data = try JSONSerialization.data(withJSONObject: object)
      let json = try #require(String(bytes: data, encoding: .utf8))
      let refused = try #require(try refusal(of: json))

      #expect(refused.kind == .usage)
      #expect(refused.message.contains("`\(field)` holds the control character '\(spelled)'"))
    }
  }

  @Test
  func `input that cannot be read is told as it was`() {
    let renderer = IntentRenderer(
      reader: MockAuthoredInput(failing: .notAFile(path: "missing.yml")),
    )

    #expect(throws: LayoutRenderingError.input(message: "'missing.yml' is not a file")) {
      try renderer.intent(readingFrom: "missing.yml")
    }
  }
}

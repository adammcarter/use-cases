import Testing
import UseCasesCore
@testable import UseCasesMCP

/// How a message is read, including the shapes a well-behaved host never sends.
struct JsonRpcRequestTests {
  private func parsed(_ text: String) throws -> JsonRpcRequest {
    try JsonRpcRequest(json: JSONParser.parse(text))
  }

  @Test
  func `a message with no id is answered with null`() throws {
    let request = try parsed(#"{"jsonrpc":"2.0","method":"tools/list"}"#)
    #expect(request.identifier == .null)
    #expect(request.method == "tools/list")
  }

  @Test(arguments: [
    (#"{"id":1,"method":"x"}"#, JSONValue.number(1)),
    (#"{"id":"abc","method":"x"}"#, JSONValue.string("abc")),
    (#"{"id":null,"method":"x"}"#, JSONValue.null),
  ])
  func `the id is echoed as it arrived`(
    text: String,
    identifier: JSONValue,
  ) throws {
    #expect(try parsed(text).identifier == identifier)
  }

  @Test
  func `params that are not an object place no arguments`() throws {
    let request = try parsed(#"{"id":1,"method":"tools/call","params":[1,2]}"#)
    #expect(request.parameters.isEmpty)
  }

  /// The method-not-found message interpolates whatever was sent, so a method
  /// that is not a string still names itself.
  @Test(arguments: [
    (#"{"id":1}"#, "<missing>"),
    (#"{"id":1,"method":null}"#, "<missing>"),
    (#"{"id":1,"method":5}"#, "5"),
    (#"{"id":1,"method":true}"#, "true"),
    (#"{"id":1,"method":"nope/thing"}"#, "nope/thing"),
  ])
  func `an unusable method still reads back`(
    text: String,
    methodText: String,
  ) throws {
    #expect(try parsed(text).methodText == methodText)
  }

  @Test
  func `a method that is not a string matches no handler`() throws {
    #expect(try parsed(#"{"id":1,"method":5}"#).method == nil)
  }
}

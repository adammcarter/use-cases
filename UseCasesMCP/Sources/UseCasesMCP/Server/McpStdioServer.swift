import Foundation
import MCP
import UseCasesCore

/// The stdio server (packages/mcp/src/index.ts `startStdioServer`).
///
/// The MCP Swift SDK supplies the byte pipe — `StdioTransport` frames
/// newline-delimited messages on stdin and stdout, non-blocking, with the
/// partial-write retry a pipe needs. The BYTES are ours: the SDK's `Server`
/// actor encodes every response with `JSONEncoder` and `.sortedKeys`, which
/// would reorder the envelope's frozen eight keys and every declared schema,
/// so responses are written by ``JSONWriter`` instead (ADR 0007 decision 8, and
/// docs/rewrite/ladder-notes.md).
///
/// Messages are handled one at a time, in arrival order, as the TypeScript's
/// line handler does.
public struct McpStdioServer: Sendable {
  private let environment: McpEnvironment

  public init(environment: McpEnvironment) {
    self.environment = environment
  }

  /// Serve until stdin closes.
  public func run() async throws {
    let transport = StdioTransport()
    try await transport.connect()
    for try await message in await transport.receive() {
      guard let response = await response(to: message) else {
        continue
      }
      try await transport.send(Data(response.jsonText.utf8))
    }
  }

  /// The answer to one framed message: nil for a blank line or a notification,
  /// both of which are met with silence.
  func response(to message: Data) async -> JsonRpcResponse? {
    // node's `chunk.toString()` replaces an invalid byte sequence rather than
    // refusing the line, and so does this; the failable initializer would
    // instead drop the message.
    // swiftlint:disable:next optional_data_string_conversion
    let line = String(decoding: message, as: UTF8.self)
    guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return nil
    }
    let parsed: JSONValue
    do throws(SchemaError) {
      // `JSON.parse` reorders integer-like keys, and a use-case row arriving
      // through a tool call is written back in the order it is read, so the
      // same reordering has to happen here.
      parsed = try JavaScriptPropertyOrder.reordered(JSONParser.parse(line))
    } catch {
      return .parseError
    }
    return await McpMessageRouter.respond(
      to: JsonRpcRequest(json: parsed),
      environment: environment,
    )
  }
}

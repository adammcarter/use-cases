import Foundation
import Testing
import UseCasesCore

/// ADR 039: the plugin, Homebrew and the downloads come from one tag, so the plugin's manifest
/// says the version the program reports.
struct PluginManifestTests {
  private func plugin(_ path: String) throws -> URL {
    try DocsFolder.url().deletingLastPathComponent().appending(path: "plugin/\(path)")
  }

  private func json(_ path: String) throws -> [String: Any] {
    let data = try Data(contentsOf: plugin(path))

    return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
  }

  // @use-case:docs.held-true#swift-tests.plugin-version
  @Test
  func `the plugin manifest carries the version the program reports`() throws {
    let manifest = try json(".claude-plugin/plugin.json")

    #expect(manifest["name"] as? String == "use-cases")
    #expect(manifest["version"] as? String == ProductVersion.current.release)
  }

  // @use-case:end docs.held-true#swift-tests.plugin-version

  // @use-case:docs.held-true#swift-tests.plugin-version
  @Test
  func `the plugin starts the program through its launcher with the mcp command`() throws {
    let servers = try #require(json(".mcp.json")["mcpServers"] as? [String: Any])
    let server = try #require(servers["use-cases"] as? [String: Any])

    #expect(server["command"] as? String == "${CLAUDE_PLUGIN_ROOT}/bin/use-cases")
    #expect(server["args"] as? [String] == ["mcp"])
    #expect(try FileManager.default.isExecutableFile(atPath: plugin("bin/use-cases").path))
  }
  // @use-case:end docs.held-true#swift-tests.plugin-version
}

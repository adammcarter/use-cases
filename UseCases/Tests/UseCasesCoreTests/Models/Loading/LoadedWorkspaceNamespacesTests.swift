import Testing
@testable import UseCasesCore

struct LoadedWorkspaceNamespacesTests {
  @Test
  func `a scope's namespace is its scopes' prefixes from the root down`(
  ) throws {
    let fixture = try WorkspaceFixture()
    try fixture.write("packages/auth/use-cases.yml", YAMLSamples.child(prefix: "auth"))
    try fixture.write("packages/auth/oauth/use-cases.yml", YAMLSamples.child(prefix: "oauth"))
    try fixture.write("packages/plain/use-cases.yml", "schema_version: 1\n")

    let namespaces = try fixture.loaded().scopeNamespaces

    #expect(
      Dictionary(
        uniqueKeysWithValues: namespaces.map { namespace in
          (namespace.scope.discovered.directory.text, namespace.text)
        },
      ) == [
        ".": "app",
        "packages/auth": "app.auth",
        "packages/auth/oauth": "app.auth.oauth",
        "packages/plain": "app",
      ],
    )
  }

  @Test
  func `a workspace with no prefix at all has an empty namespace`() throws {
    let fixture = try WorkspaceFixture(rootConfiguration: "schema_version: 1\nroot: true\n")

    #expect(try fixture.loaded().scopeNamespaces.map(\.text) == [""])
  }
}

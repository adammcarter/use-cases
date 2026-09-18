import UseCasesCore

/// Reads one resource (packages/mcp/src/resources.ts `readMcpResource`).
///
/// A repo-scoped resource resolves its workspace from the URI's `?repo=` or the
/// server's configured default. The repo is bound, symlink-safe, to an allowed
/// root — the configured default, else the server's working directory — and a
/// traversal is rejected BEFORE any disk read. Schema resources need no repo.
public enum McpResourceReader {
  public static func read(
    uri text: String,
    environment: McpEnvironment,
  ) -> McpResourceOutcome {
    guard let uri = McpResourceUri(text) else {
      return .failure(
        code: McpResourceOutcome.resourceNotFound,
        message: "Unknown resource: \(text)",
      )
    }

    // Schema resources are the contract an integrator depends on, and it
    // belongs to no one repo.
    if uri.key == "schemas" {
      return schemaIndex(text)
    }
    if uri.key.hasPrefix("schemas/") {
      return schema(named: String(uri.key.dropFirst("schemas/".count)), uri: text)
    }

    let workspace: ResolvedWorkspaceContext
    switch context(for: uri.repository, environment: environment) {
    case let .failure(code, message):
      return .failure(code: code, message: message)
    case let .resolved(resolved):
      workspace = resolved
    }

    let view = McpResourceViews.view(for: uri.key)
    guard let view else {
      return .failure(
        code: McpResourceOutcome.resourceNotFound,
        message: "Unknown resource: \(text)",
      )
    }
    do throws(McpToolFailure) {
      return try .contents(uri: text, payload: view(workspace, environment))
    } catch {
      // The TypeScript lets a core failure escape the line handler, which ends
      // the process. A server that dies on a damaged ledger is worse than one
      // that says so, so it is reported as an internal error instead. Recorded
      // as a divergence in docs/rewrite/ladder-notes.md.
      return .failure(code: -32603, message: error.message)
    }
  }

  private enum ContextOutcome {
    case resolved(ResolvedWorkspaceContext)
    case failure(code: Int, message: String)
  }

  private static func context(
    for repositoryFromUri: String?,
    environment: McpEnvironment,
  ) -> ContextOutcome {
    guard let repository = repositoryFromUri ?? environment.configuredRepository,
          !repository.isEmpty
    else {
      return .failure(
        code: McpResourceOutcome.invalidParameters,
        message: "This resource requires a repo: add ?repo=<path> to the URI or "
          + "set UCM_MCP_REPO.",
      )
    }
    // SECURITY: the boundary is the configured repo when there is one, else the
    // server's own directory. A `?repo=` that climbs out never reaches disk.
    let allowedRoot = environment.configuredRepository.map { configured in
      WorkspacePath.absolute(configured, relativeTo: environment.workingDirectory)
    } ?? environment.workingDirectory
    let workspaceRoot: String
    do throws(PathError) {
      workspaceRoot = try PathContainment.resolveContained(
        root: allowedRoot,
        candidate: repository,
        message: "repo escapes the allowed workspace root boundary.",
      )
    } catch {
      return .failure(
        code: McpResourceOutcome.invalidParameters,
        message: "UCM_PATH_ESCAPE: \(error.message)",
      )
    }
    do throws(McpToolFailure) {
      let registry = try McpSchemaRegistry.load()
      do throws(WorkspaceError) {
        return try .resolved(WorkspaceContextResolver.resolve(
          options: ResolveWorkspaceContextOptions(workspaceRoot: workspaceRoot),
          registry: registry,
        ))
      } catch {
        throw McpToolFailure(error)
      }
    } catch {
      return .failure(code: -32603, message: error.message)
    }
  }

  /// `use-cases://schemas`: the index, with a readable name and the URI each schema
  /// reads at.
  private static func schemaIndex(_ uri: String) -> McpResourceOutcome {
    let schemas: [PublicSchema]
    do throws(McpToolFailure) {
      schemas = try McpSchemaRegistry.load().publicSchemas()
    } catch {
      return .failure(code: -32603, message: error.message)
    }
    let entries = schemas.map { schema in
      let base = basename(of: schema.identifier)
      return JSONValue.object(JSONObject([
        ("id", .string(schema.identifier)),
        ("name", .string(base)),
        ("uri", .string("use-cases://schemas/\(base)")),
      ]))
    }
    return .contents(uri: uri, payload: .object(JSONObject([
      ("schema_version", .number(1)),
      ("schemas", .array(entries)),
    ])))
  }

  /// `use-cases://schemas/{name}`: matched on the full id, the file name, or the name
  /// without its `.schema.json` suffix.
  private static func schema(
    named name: String,
    uri: String,
  ) -> McpResourceOutcome {
    let schemas: [PublicSchema]
    do throws(McpToolFailure) {
      schemas = try McpSchemaRegistry.load().publicSchemas()
    } catch {
      return .failure(code: -32603, message: error.message)
    }
    let found = schemas.first { schema in
      let base = basename(of: schema.identifier)
      let short = base.hasSuffix(".schema.json")
        ? String(base.dropLast(".schema.json".count))
        : base
      return schema.identifier == name || base == name || short == name
    }
    guard let found else {
      return .failure(
        code: McpResourceOutcome.resourceNotFound,
        message: "Unknown schema: \(name)",
      )
    }
    // A schema that did not load has no body at all, and `JSON.stringify`
    // leaves an undefined member out rather than writing null.
    var payload = JSONObject([("id", .string(found.identifier))])
    payload["schema"] = found.schema
    return .contents(uri: uri, payload: .object(payload))
  }

  /// `id.split("/").pop() ?? id`.
  private static func basename(of identifier: String) -> String {
    identifier.split(separator: "/", omittingEmptySubsequences: false).last.map(String.init)
      ?? identifier
  }
}

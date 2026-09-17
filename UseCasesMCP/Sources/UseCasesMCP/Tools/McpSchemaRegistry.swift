import UseCasesCore

/// Loads the schemas embedded in the binary. The core is linked in, so there is
/// no missing build to report; a schema set that fails to load is the thrown
/// failure it is.
public enum McpSchemaRegistry {
  public static func load() throws(McpToolFailure) -> SchemaRegistry {
    do throws(SchemaError) {
      return try SchemaRegistry()
    } catch {
      throw McpToolFailure(error)
    }
  }
}

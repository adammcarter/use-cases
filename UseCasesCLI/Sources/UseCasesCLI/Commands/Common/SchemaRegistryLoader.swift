import UseCasesCore

/// Loads the schemas embedded in the binary — the Swift counterpart of the
/// TypeScript CLI's core loader. The core is linked in, so there is no missing
/// build to report; a schema set that fails to load is reported as the thrown
/// failure it is.
enum SchemaRegistryLoader {
  static func load() throws(CommandFailure) -> SchemaRegistry {
    do {
      return try SchemaRegistry()
    } catch {
      throw CommandFailure(error)
    }
  }
}

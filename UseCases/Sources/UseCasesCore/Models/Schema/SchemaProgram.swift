/// A schema compiled for checking: every schema object as a node, and where the document's own
/// schema starts.
struct SchemaProgram: Equatable, Sendable {
  let nodes: [SchemaNode]
  let root: Int
}

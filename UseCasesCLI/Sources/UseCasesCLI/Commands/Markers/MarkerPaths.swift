/// Where a marker command looks: the product root its markers and verifiers
/// are scoped to, and the bindings and proof ledgers.
struct MarkerPaths: Equatable {
  let productRoot: String
  let bindingsPath: String
  let evidencePath: String
}

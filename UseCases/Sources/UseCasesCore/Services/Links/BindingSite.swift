/// A manual binding with the binding it names and the definition file it is written in.
struct BindingSite: Sendable {
  let binding: ManualBinding
  let identity: LinkIdentity

  /// The definition file of the use case: where a problem with the binding is filed.
  let definition: WorkspacePath
}

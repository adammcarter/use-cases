/// The root `use-case-groups.yml` once it passed its schema (chapter 03): the groups in the
/// order written.
struct GroupsFile: Equatable, Sendable {
  let groups: [GroupDefinition]
}

/// The declarative command registry (packages/cli/src/command/registry.ts), in
/// the TypeScript's order. Help, unknown-flag detection and dispatch all derive
/// from it, so every command is declared here whether or not its port has
/// landed. `version`, `init` and help are builtins, not registry commands.
enum CommandRegistry {
  static let allCommands: [CommandSpecification] = [
    SchemaCommands.all,
    MatrixCommands.all,
    PlanCommands.all,
    CapsuleCommands.all,
    EvidenceCommands.all,
    WorkflowCommands.all,
    DoctorCommands.all,
    MarkersCommands.all,
    KeygenCommands.all,
    RecoverCommands.all,
    ShowcaseCommands.all,
    ApproveRunCommands.all,
  ].flatMap(\.self)
}

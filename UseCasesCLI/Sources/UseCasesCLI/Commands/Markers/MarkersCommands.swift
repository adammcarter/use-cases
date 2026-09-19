/// The marker commands (packages/cli/src/commands/markers.ts). The bindings
/// commands are specified in `MarkersCommands+Bindings.swift` and run in
/// `MarkersCommands+BindingRuns.swift`; the trust commands in
/// `MarkersCommands+Trust.swift`, run in `MarkersCommands+ScanRuns.swift` and
/// `MarkersCommands+ProveRuns.swift`.
enum MarkersCommands {
  static let all = [
    bind,
    unbind,
    rebind,
    scan,
    impact,
    prove,
    verify,
    validateLedger,
  ]
}

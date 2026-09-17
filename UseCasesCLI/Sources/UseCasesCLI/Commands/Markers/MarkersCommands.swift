/// The marker commands, declared for help and flag checking. Their port is
/// ladder row 4c; until it lands each one refuses with `cli_not_yet_ported`.
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

/// The showcase commands, declared for help and flag checking. Their port is
/// ladder row 4e; until it lands each one refuses with `cli_not_yet_ported`.
enum ShowcaseCommands {
  static let all = [
    start,
    recordObservation,
    recordVerdict,
    decide,
    pause,
    resume,
    finish,
    status,
    requestApproval,
    approve,
    reject,
    correct,
  ]
}

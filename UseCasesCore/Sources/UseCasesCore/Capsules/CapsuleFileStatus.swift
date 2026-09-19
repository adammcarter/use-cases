/// What happened to one file under `demo-capsules/`. The raw values are the
/// TypeScript's `CapsuleFileResult["status"]`.
public enum CapsuleFileStatus: String, Sendable, Equatable, CaseIterable {
  case loaded
  case parseError = "parse_error"
  case schemaError = "schema_error"
  case inputOutputError = "io_error"
  case symlinkRejected = "symlink_rejected"
  case pathEscape = "path_escape"
}

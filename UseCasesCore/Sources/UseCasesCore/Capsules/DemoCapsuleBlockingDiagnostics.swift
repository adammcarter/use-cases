/// The diagnostics that block a capsule run before anything is written.
struct DemoCapsuleBlockingDiagnostics: Error {
  let diagnostics: [Diagnostic]
}

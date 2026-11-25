/// A run that has been published and is held by the request that made it: nobody can finish,
/// abort or seal it meanwhile (chapter 12 §18).
struct HeldRun: Sendable {
  let run: OpenRun
  let lock: HeldRunLock
}

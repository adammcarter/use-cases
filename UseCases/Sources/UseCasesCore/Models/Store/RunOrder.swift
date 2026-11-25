/// The allocation high-water mark (`run-order.json`, chapter 12 §9): allocation metadata, not
/// evidence. Every new run id is greater than `lastRunIdentifier`.
struct RunOrder: Equatable, Sendable {
  let lastRunIdentifier: RunIdentifier
}

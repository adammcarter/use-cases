/// What a `showcase_record_verdict` call has settled on before anything is
/// appended: the run, the item, the verdict, and the observation the verdict
/// rests on — which the run's replay, not the caller, supplied.
struct McpVerdictRequest {
  let runIdentifier: String
  let itemIdentifier: String
  let verdict: String
  let observationEventIdentifier: String
}

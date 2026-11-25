/// What a person typed when `record --interactive` asked: ids of the use case and route, as the
/// store spells them, and the words for the rest.
struct RecordAnswers: Equatable {
  let useCase: String
  let route: String
  let status: String
  let message: String?
}

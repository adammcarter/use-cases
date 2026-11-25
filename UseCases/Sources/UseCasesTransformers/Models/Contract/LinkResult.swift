/// One result for one validation link.
struct LinkResult: Encodable, Equatable, Sendable {
  let link: String
  let status: ResultStatus
  /// Opaque test ids; omitted from the document when nil.
  let tests: [String]?
  /// A short note for people; omitted from the document when nil.
  let message: String?

  init(
    link: String,
    status: ResultStatus,
    tests: [String]? = nil,
    message: String? = nil,
  ) {
    self.link = link
    self.status = status
    self.tests = tests
    self.message = message
  }
}

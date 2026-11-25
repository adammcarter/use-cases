/// A test a transformer reported that sits inside no link (chapter 12 §11).
struct UnlinkedTest: Equatable, Sendable {
  let test: String
  let file: String?
  let line: Int?
  let status: Verdict
}

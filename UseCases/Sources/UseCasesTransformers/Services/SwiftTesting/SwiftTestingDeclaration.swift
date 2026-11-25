/// Where Swift Testing says a test function is declared.
struct SwiftTestingDeclaration: Equatable, Sendable {
  let file: String?
  let line: Int?
}

/// Lays a sign-off out as ``YAMLLayout/useCaseFile`` says.
struct ApprovalSerialiser: ApprovalSerialising {
  private let emitter: any YAMLEmitting

  init(emitter: any YAMLEmitting = YAMLEmitter(layout: .useCaseFile)) {
    self.emitter = emitter
  }

  func lines(
    of approval: Approval,
    indent: Int,
  ) -> [String] {
    let margin = String(repeating: " ", count: indent)

    return emitter.lines(of: .members(["approved": approval.document])).map { line in
      line.isEmpty ? line : margin + line
    }
  }
}

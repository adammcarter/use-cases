import UseCasesCore

extension SignOffCounts {
  /// Who signs: the person for critical and core, an agent for supporting where the person said
  /// it may; `nil` when nothing needs a signature.
  var words: String? {
    var yours: [String] = []

    if critical > 0 {
      yours.append("\(critical) critical")
    }

    if core > 0 {
      yours.append("\(core) core")
    }

    if untiered > 0 {
      yours.append("\(untiered) without a tier")
    }

    var parts: [String] = []

    if !yours.isEmpty {
      parts.append("yours: \(yours.joined(separator: ", "))")
    }

    if supporting > 0 {
      parts.append("supporting: \(supporting) (an agent's, where you said it may)")
    }

    return parts.isEmpty ? nil : parts.joined(separator: " · ")
  }
}

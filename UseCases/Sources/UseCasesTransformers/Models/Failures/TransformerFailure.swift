/// Why a transformer could not answer. Each one ends the program with a message on stderr and a
/// non-zero exit, which the core reports as a run error and never as a failed use case
/// (chapter 10 §14).
enum TransformerFailure: Error, Equatable {
  case missingArguments
  case unknownTransformer(String)
  case unsupportedJob(transformer: String, job: String)
  case requestUnreadable(path: String, reason: String)
  case requestMalformed(reason: String)
  case unsupportedContract(Int?)
  case settingMissing(String)
  case settingInvalid(name: String, expected: String)
  case reportUnreadable(path: String, reason: String)
  case reportMalformed(path: String, reason: String)
  case responseUnwritable(path: String, reason: String)

  /// Wrong use of the program rather than a problem with the work: exit code 2.
  var isUsageError: Bool {
    switch self {
    case .missingArguments, .unknownTransformer, .unsupportedJob:
      true
    default:
      false
    }
  }
}

extension TransformerFailure: CustomStringConvertible {
  var description: String {
    switch self {
    case .missingArguments:
      "usage: use-cases-transformers <transformer> <links|results> <request.json> <response.json>"
    case let .unknownTransformer(name):
      "unknown transformer '\(name)'. The bundled transformers are "
        + TransformerCatalogue.names.joined(separator: ", ")
    case let .unsupportedJob(transformer, job):
      "\(transformer) does not do the \(job) job"
    case let .requestUnreadable(path, reason):
      "cannot read the request \(path): \(reason)"
    case let .requestMalformed(reason):
      "the request is malformed: \(reason)"
    case let .unsupportedContract(version):
      "unsupported contract \(version.map(String.init) ?? "(none)"): this program speaks contract 1"
    case let .settingMissing(name):
      "settings.\(name) is required"
    case let .settingInvalid(name, expected):
      "settings.\(name) must be \(expected)"
    case let .reportUnreadable(path, reason):
      "cannot read the report \(path): \(reason)"
    case let .reportMalformed(path, reason):
      "the report \(path) is malformed: \(reason)"
    case let .responseUnwritable(path, reason):
      "cannot write the response \(path): \(reason)"
    }
  }
}

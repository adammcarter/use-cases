/// The results of every source, merged by link (chapter 13 §9).
struct Heard {
  /// The worst verdict any source gave each link.
  let verdicts: [String: Verdict]

  /// Which sources gave each link a result, in the order of the bridge settings.
  private let speakers: [String: [IdentifierSegment]]

  init(_ sources: [SourceOutcome]) {
    var verdicts: [String: Verdict] = [:]
    var speakers: [String: [IdentifierSegment]] = [:]

    for source in sources {
      for result in source.results {
        if let known = verdicts[result.link] {
          verdicts[result.link] = known.worse(than: result.status)
        } else {
          verdicts[result.link] = result.status
        }

        speakers[result.link, default: []].append(source.identifier)
      }
    }

    self.verdicts = verdicts
    self.speakers = speakers
  }

  /// The sources that gave at least one of these links a result, each once, in the order they
  /// first spoke.
  func sources(speakingFor keys: [String]) -> [IdentifierSegment] {
    var found: [IdentifierSegment] = []

    for key in keys {
      for source in speakers[key] ?? [] where !found.contains(source) {
        found.append(source)
      }
    }

    return found
  }
}

import ArgumentParser

/// The four layouts people read (chapter 21 §7).
enum RenderKind: String, CaseIterable, ExpressibleByArgument {
  case intent
  case brief
  case proposal
  case results
}

import Foundation
import Testing

//: @use-case:skills.assets.demo_gates
/// The black-box oracle for skills/assets.yml, row `demo_gates`.
///
/// It reads the LIVE `skills/showcase/SKILL.md` — the body every host actually
/// loads — rather than a snapshot. `SkillsGoldenCorpus` pins a FROZEN copy of
/// the shipped skills, so editing a real skill body fails nothing there; this
/// file is what makes a skill drifting from what its row promises break the
/// build (ADR 0007 row 10d, replacing `tests/skills/p7-skills.test.ts`).
///
/// The subject is a shipped artefact, not the product, so nothing here imports
/// UseCasesCore: the skill is read as a file and asserted as text, which is
/// exactly what a host does with it.
///
/// Self-contained: a shared oracle file means one edit stales every row bound
/// to it.
struct SkillsAssetsDemoGatesTests {
  static func showcaseSkill() throws -> String {
    try String(
      contentsOfFile: "\(OracleLayout.repositoryRoot)/skills/showcase/SKILL.md",
      encoding: .utf8,
    )
  }

  /// Reads the live body and fails with the phrase that went missing, so a
  /// drifting skill names its own regression rather than reporting `false`.
  static func expect(
    _ pattern: String,
    _ why: String,
    in body: String,
    sourceLocation: SourceLocation = #_sourceLocation,
  ) {
    #expect(
      OracleText.contains(pattern, in: body),
      Comment(
        rawValue: "skills/showcase/SKILL.md must still say \(why) (/\(pattern)/)",
      ),
      sourceLocation: sourceLocation,
    )
  }

  // golden_gates, first half. The card is the demo and the question is only its
  // confirm button: a skill that dropped the card would leave the gates asking
  // about something the user never saw.
  @Test
  func `the demo card loop is the skill's spine and the card is the demo`() throws {
    let body = try Self.showcaseSkill()

    #expect(body.contains("## The Demo Card Loop"))
    Self.expect("(?i)card is the demo", "the card is the demo", in: body)
    #expect(body.contains("**Actual**"), "a reprinted card carries what actually happened")
    Self.expect("(?i)card grows", "the card grows rather than mutating", in: body)
  }

  // golden_gates, second half. No live run starts before an explicit ready
  // answer, the driver is chosen, and the verdict is asked in the fixed order.
  @Test
  func `no live run starts before an explicit ready answer`() throws {
    let body = try Self.showcaseSkill()

    Self.expect("Gate 1[\\s\\S]{0,300}ready", "Gate 1 asks whether the user is ready", in: body)
    Self.expect(
      "(?i)never start from inference",
      "a run never starts from inference",
      in: body,
    )
    Self.expect("Gate 2[\\s\\S]{0,200}who drives", "Gate 2 asks who drives", in: body)
    #expect(
      body.contains("Approve, Reject, Run it again"),
      "the verdict is offered in that fixed order",
    )
    Self.expect("(?i)notes", "an answer may carry the user's notes", in: body)
  }

  // bad_question_before_its_card. A question in the same message as its card
  // hides the card on hosts that flush assistant text at turn end, so the card
  // has to be its own completed message and the retry has to repost it.
  @Test
  func `no question is ever asked before its card has been delivered`() throws {
    let body = try Self.showcaseSkill()

    #expect(body.contains("OWN message"), "the card is posted as its own message")
    Self.expect("(?i)end(s)? the turn", "the turn ends before any question", in: body)
    Self.expect(
      "(?i)never rides in the same message",
      "a question never rides in the same message as its card",
      in: body,
    )
    Self.expect(
      "(?i)re-composes from the card",
      "a retry re-composes from the card",
      in: body,
    )
    Self.expect("(?i)repost", "a retry reposts the card", in: body)
  }

  // bad_reject_is_recorded_verbatim. The gates change how an answer is
  // collected, never what it is worth: reject goes through the reject command
  // with the user's own words, and the signed tier stays a separate opt-in.
  @Test
  func `a reject answer is recorded verbatim and the signed tier stays separate`() throws {
    let body = try Self.showcaseSkill()

    #expect(
      body.contains("`use-cases showcase reject"),
      "a reject answer is recorded through the reject command",
    )
    Self.expect(
      "(?i)a tap, not typed text",
      "a tapped answer carries the trust a typed one did",
      in: body,
    )
    Self.expect(
      "(?i)opt-in release/audit path",
      "the signed sign-off tier is the separate opt-in path",
      in: body,
    )
    Self.expect("(?i)explicit", "the boundary stays explicit", in: body)
  }

  // edge_run_it_again_and_talking_record_nothing. Both answers are escape
  // hatches: neither may leave a verdict behind.
  @Test
  func `run it again and talking about it both record nothing`() throws {
    let body = try Self.showcaseSkill()

    Self.expect(
      "(?i)run it again[\\s\\S]{0,200}recording nothing",
      "run it again re-performs and re-asks without recording",
      in: body,
    )
    #expect(
      body.contains("showcase pause"),
      "talking about it maps to pause, which records no verdict",
    )
  }
}

//: @use-case:end skills.assets.demo_gates

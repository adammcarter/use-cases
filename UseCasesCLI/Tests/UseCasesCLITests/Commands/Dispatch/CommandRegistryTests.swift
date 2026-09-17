import Testing
@testable import UseCasesCLI

/// The registry declares the TypeScript's 44 commands, in its order, under its
/// ids — help, unknown-flag detection and dispatch all derive from it.
struct CommandRegistryTests {
  static let expected: [(path: String, command: String)] = [
    ("schema list", "schema.list"),
    ("schema validate-fixtures", "schema.validate-fixtures"),
    ("matrix validate", "matrix.validate"),
    ("matrix list", "matrix.list"),
    ("matrix status", "matrix.status"),
    ("matrix upsert", "matrix.upsert"),
    ("matrix remove", "matrix.remove"),
    ("plan showcase", "plan.showcase"),
    ("plan walkthrough", "plan.walkthrough"),
    ("plan cards", "plan.cards"),
    ("capsule list", "capsule.list"),
    ("capsule validate", "capsule.validate"),
    ("capsule plan", "capsule.plan"),
    ("capsule run", "capsule.run"),
    ("evidence record", "evidence.record"),
    ("evidence status", "evidence.status"),
    ("evidence void", "evidence.void"),
    ("workflow set-mode", "workflow.set-mode"),
    ("workflow mode", "workflow.get-mode"),
    ("doctor skills", "doctor.skills"),
    ("doctor roots", "doctor.roots"),
    ("bind", "markers.bind"),
    ("unbind", "markers.unbind"),
    ("rebind", "markers.rebind"),
    ("scan", "markers.scan"),
    ("impact", "markers.impact"),
    ("prove", "markers.prove"),
    ("verify", "markers.verify"),
    ("validate-ledger", "markers.validate-ledger"),
    ("keygen", "markers.keygen"),
    ("recover", "markers.recover"),
    ("showcase start", "showcase.start"),
    ("showcase record-observation", "showcase.record-observation"),
    ("showcase record-verdict", "showcase.record-verdict"),
    ("showcase decide", "showcase.decide"),
    ("showcase pause", "showcase.pause"),
    ("showcase resume", "showcase.resume"),
    ("showcase finish", "showcase.finish"),
    ("showcase status", "showcase.status"),
    ("showcase request-approval", "showcase.request-approval"),
    ("showcase approve", "showcase.approve"),
    ("showcase reject", "showcase.reject"),
    ("showcase correct", "showcase.correct"),
    ("approve-run", "showcase.approve_run"),
  ]

  @Test
  func `declares every TypeScript command in order`() {
    let declared = CommandRegistry.allCommands.map { command in
      "\(command.path.joined(separator: " ")) -> \(command.command)"
    }

    let expected = Self.expected.map { pair in
      "\(pair.path) -> \(pair.command)"
    }
    #expect(declared == expected)
  }

  @Test
  func `hides only doctor skills`() {
    let hidden = CommandRegistry.allCommands.filter(\.isHidden).map(\.command)

    #expect(hidden == ["doctor.skills"])
  }

  @Test(arguments: [
    "schema.list",
    "schema.validate-fixtures",
    "workflow.set-mode",
    "workflow.get-mode",
    "doctor.skills",
    "doctor.roots",
  ])
  func `marks the row 4a commands as ported`(command: String) throws {
    let specification = try #require(CommandRegistry.allCommands.first { $0.command == command })

    #expect(specification.isPorted)
  }

  @Test
  func `marks exactly the row 4a commands as ported`() {
    let ported = CommandRegistry.allCommands.filter(\.isPorted)

    #expect(ported.count == 6)
  }
}

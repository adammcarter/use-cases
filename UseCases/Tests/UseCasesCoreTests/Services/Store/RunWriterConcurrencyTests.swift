import Foundation
import Testing
@testable import UseCasesCore

struct RunWriterConcurrencyTests {
  private static let writers = 12

  /// Every writer reads the same clock and the same random bits, so each one computes the same id
  /// for itself. Only the allocation lock keeps them apart.
  @Test
  func `writers recording at once each get their own run and none is lost`() async throws {
    let directory = try TemporaryDirectory()
    let workspace = directory.url

    let identifiers = try await withThrowingTaskGroup(of: RunIdentifier.self) { group in
      for number in 0 ..< Self.writers {
        group.addTask {
          let writer = try RunWriter(
            clock: FixedTimekeeper(),
            random: FixedRandomBits(),
          )
          let run = try writer.openRun(
            kind: .record,
            in: workspace,
          )

          try writer.append(
            WriterFixture.result(
              .pass,
              route: "route-\(number)",
            ),
            to: run,
          )
          _ = try writer.seal(
            run,
            termination: .completed,
          )

          return run.identifier
        }
      }

      var found: [RunIdentifier] = []
      for try await identifier in group {
        found.append(identifier)
      }

      return found
    }

    #expect(Set(identifiers).count == Self.writers)

    let history = try StoreReader().readHistory(in: workspace)
    #expect(history.runs.map(\.identifier) == identifiers.sorted())
    #expect(history.unfinishedRuns.isEmpty)
    #expect(history.runs.allSatisfy { $0.results.count == 1 })

    let order = try #require(try RunOrderReader().readRunOrder(in: workspace))
    #expect(order.lastRunIdentifier == identifiers.max())
  }

  @Test
  func `ids allocated at once are consecutive when the clock and the bits are the same`(
  ) async throws {
    let directory = try TemporaryDirectory()
    let workspace = directory.url

    let identifiers = try await withThrowingTaskGroup(of: RunIdentifier.self) { group in
      for _ in 0 ..< Self.writers {
        group.addTask {
          try RunWriter(
            clock: FixedTimekeeper(),
            random: FixedRandomBits(),
          ).openRun(
            kind: .record,
            in: workspace,
          ).identifier
        }
      }

      var found: [RunIdentifier] = []
      for try await identifier in group {
        found.append(identifier)
      }

      return found.sorted()
    }

    let numbers = identifiers.map(RunNumber.init(identifier:))
    #expect(numbers.dropFirst() == ArraySlice(numbers.compactMap(\.successor).dropLast()))
  }
}

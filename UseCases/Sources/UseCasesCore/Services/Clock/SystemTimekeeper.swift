import Foundation

/// The clock of this machine.
struct SystemTimekeeper: Timekeeping {
  func now() -> Date {
    Date()
  }
}

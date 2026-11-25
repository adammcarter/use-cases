/// The one flag a signal handler sets, and the supervisor reads.
///
/// A handler is a plain C function with no context, so what it writes has to be a global, and it
/// may do nothing a signal can break: no lock, no allocation. The flag is a single 32-bit cell
/// allocated once and never freed, reached through a raw pointer. A store or a load of an aligned
/// 32-bit integer is one instruction, so a handler that lands between two reads cannot tear it,
/// and a raw pointer is not tracked by the runtime's exclusivity checks, which a plain global
/// variable is, and which abort the process when a handler writes while another thread reads.
/// (An `Atomic` would say the same in the type system, but needs macOS 15.)
enum ProcessSignalFlag {
  private nonisolated(unsafe) static let cell: UnsafeMutablePointer<Int32> = {
    let cell = UnsafeMutablePointer<Int32>.allocate(capacity: 1)
    cell.initialize(to: 0)

    return cell
  }()

  static var isRaised: Bool {
    cell.pointee != 0
  }

  /// Makes the cell before any handler can run, so a handler never makes it: making it takes a
  /// lock a signal could interrupt.
  static func prepare() {
    _ = cell
  }

  /// What a handler does.
  static func raise() {
    cell.pointee = 1
  }

  static func clear() {
    cell.pointee = 0
  }
}

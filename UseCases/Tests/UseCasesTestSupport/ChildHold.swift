import Atomics
import Foundation

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

/// A named pipe a child shell holds on, at no cost, until the test lets it go: in place of a
/// child kept alive by sleeping.
///
/// The test holds the only write end and never writes. The child opens the pipe itself, says on a
/// ready signal that it has, and then reads: the read waits until the test lets go, then finds
/// the end of the file. Letting go leaves a mark beside the pipe before the write end closes, so
/// the child can tell the end of the file from a read that a signal ended early. A signal the
/// child traps or ignores leaves it reading again, in the shell itself, so no process is started
/// once a signal has come. One child per hold.
public final class ChildHold: Sendable {
  public let url: URL

  private let ready: ChildSignal
  private let releaseMark: String
  private let writeEnd: Int32
  private let isWriteEndClosed: ManagedAtomic<Bool>
  private let isReleaseAsked: ManagedAtomic<Bool>
  private let isHeld: ManagedAtomic<Bool>
  private let announcement: Task<String?, Never>

  /// Makes the hold's named pipe at `url`, and its ready signal beside it, neither of which may
  /// exist yet.
  public init(at url: URL) throws(NamedPipeFailure) {
    try NamedPipe.make(at: url)

    let writeDescriptor = try Self.writeEnd(of: url)

    do {
      ready = try ChildSignal(at: URL(fileURLWithPath: url.path + "-ready"))
    } catch {
      NamedPipe.release(writeDescriptor)

      throw error
    }

    let isWriteEndClosed = ManagedAtomic<Bool>(false)
    let isReleaseAsked = ManagedAtomic<Bool>(false)
    let isHeld = ManagedAtomic<Bool>(false)
    let ready = ready
    let releaseMark = url.path + "-released"

    self.url = url
    self.releaseMark = releaseMark
    self.isWriteEndClosed = isWriteEndClosed
    self.isReleaseAsked = isReleaseAsked
    self.isHeld = isHeld
    writeEnd = writeDescriptor
    announcement = Task {
      let announced: String?

      do {
        announced = try await ready.next()
      } catch {
        // Never cancelled, so this is not reached.
        announced = nil
      }

      isHeld.store(
        true,
        ordering: .sequentiallyConsistent,
      )

      if isReleaseAsked.load(ordering: .sequentiallyConsistent) {
        Self.letGo(
          writeDescriptor,
          isWriteEndClosed,
          marking: releaseMark,
        )
      }

      return announced
    }
  }

  /// The paths go first, so a child that reaches the hold after this finds no pipe there and ends,
  /// rather than waiting for ever on a pipe nobody keeps. A child held here is let go.
  deinit {
    NamedPipe.remove(url)
    Self.letGo(
      writeEnd,
      isWriteEndClosed,
      marking: releaseMark,
    )
    ready.close()
  }

  /// The shell text that holds a script here until the test lets go. The shell opens the pipe,
  /// then reads it until the end of the file in a child that first announces `value` on the
  /// ready signal, so whenever the test hears it, the shell is already waiting on that child and
  /// runs a trap the moment the child is stopped. The end of the file ends the child well, and
  /// the script goes on. A child stopped by a signal fails, and the shell then reads the pipe to
  /// its end itself, with builtins only: it never starts another child once a signal has come,
  /// because a child started while a process group is being signalled can be missed by that
  /// signal and outlive the group. A read ends without a line both at the end of the file and,
  /// in some shells (dash), when a trapped signal arrives, so the shell goes on only once the
  /// release mark is there, or once the test process is gone and can never let go; otherwise it
  /// reads again. `value` is left for the holding shell to expand; `$$` is its process ID.
  public func shellText(announcing value: String = "$$") -> String {
    let announcingRead = "'echo \"$1\" > \"$2\"; exec cat'"
    let readingOn = "while :; do read -r line <&8 && continue; "
      + "[ -e \(NamedPipe.shellWord(URL(fileURLWithPath: releaseMark))) ] && break; "
      + "kill -0 \(getpid()) 2>/dev/null || break; done"

    return "exec 8<\(NamedPipe.shellWord(url)); "
      + "/bin/sh -c \(announcingRead) held \(value) \(NamedPipe.shellWord(ready.url)) <&8 "
      + "|| " + readingOn
  }

  /// Returns once the child has opened the hold, with the value it announced; nil if the hold
  /// was given up before any child announced.
  public func waitUntilHeld() async -> String? {
    await announcement.value
  }

  /// Gives up waiting for the child to announce: a wait until held that is under way returns nil,
  /// and so does every later one, unless the child had already announced. For a test that has
  /// seen the child will never come, so no wait is left suspended for the rest of the run. Only
  /// for then: a child that reached the hold after a give up and a release would find no writer,
  /// and wait to open it for as long as this process lives.
  public func giveUp() {
    ready.close()
  }

  /// Wakes a child reading on the hold without letting it go: it reads one empty line, and reads
  /// on. A shell puts off the trap for a signal that comes just before its read begins until the
  /// read returns; this makes the read return, so such a trap runs now. Changes nothing once the
  /// hold is released.
  public func nudge() {
    guard !isWriteEndClosed.load(ordering: .sequentiallyConsistent) else {
      return
    }

    let line: [UInt8] = [0x0A]

    _ = line.withUnsafeBytes { bytes in
      write(writeEnd, bytes.baseAddress, bytes.count)
    }
  }

  /// Lets the child go on. A child that has not reached the hold yet is let go as soon as it
  /// announces, so it never waits on a hold nobody keeps. Releasing again changes nothing.
  public func release() {
    isReleaseAsked.store(
      true,
      ordering: .sequentiallyConsistent,
    )

    if isHeld.load(ordering: .sequentiallyConsistent) {
      Self.letGo(
        writeEnd,
        isWriteEndClosed,
        marking: releaseMark,
      )
    }
  }

  /// Opens the write end of the named pipe at `url`. A read end lets it open without waiting for a
  /// reader, and is closed at once: the child opens its own.
  private static func writeEnd(of url: URL) throws(NamedPipeFailure) -> Int32 {
    let readDescriptor = try NamedPipe.descriptor(
      opening: url,
      flags: O_RDONLY | O_NONBLOCK | O_CLOEXEC,
    )

    defer {
      NamedPipe.release(readDescriptor)
    }

    return try NamedPipe.descriptor(
      opening: url,
      flags: O_WRONLY | O_CLOEXEC,
    )
  }

  /// Leaves the release mark, then closes the write end, once: a child reading on finds the mark
  /// whenever it finds the end of the file.
  private static func letGo(
    _ descriptor: Int32,
    _ isClosed: ManagedAtomic<Bool>,
    marking releaseMark: String,
  ) {
    if !isClosed.exchange(true, ordering: .acquiringAndReleasing) {
      _ = FileManager.default.createFile(
        atPath: releaseMark,
        contents: nil,
      )
      NamedPipe.release(descriptor)
    }
  }
}

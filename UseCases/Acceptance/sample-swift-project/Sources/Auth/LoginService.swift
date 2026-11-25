public enum LoginError: Error, Equatable {
    case invalidCredentials
    case lockedOut
}

public struct User: Equatable {
    public let id: String
}

public final class LoginService {
    private var failures = 0
    public init() {}

    // @use-case:shop.login.authenticate#check-credentials
    public func authenticate(username: String, password: String) throws -> User {
        guard failures < 3 else { throw LoginError.lockedOut }
        guard username == "sam@example.com", password == "correct-password" else {
            failures += 1
            throw LoginError.invalidCredentials
        }
        return User(id: "user-1")
    }
    // @use-case:end shop.login.authenticate#check-credentials

    // @use-case:shop.login.lockout#lock-after-failures
    public var isLockedOut: Bool {
        failures >= 5 // BUG on purpose: spec says 3
    }
    // @use-case:end shop.login.lockout#lock-after-failures

    // @use-case:shop.login.remember-me#persist-session
    public func rememberSession(for user: User) -> String {
        "session-\(user.id)"
    }
    // @use-case:end shop.login.remember-me#persist-session

    // @use-case:shop.login.password-reset#send-reset
    public func sendReset(to username: String) -> Bool {
        !username.isEmpty
    }
    // @use-case:end shop.login.password-reset#send-reset

    public func unrelatedHelper() -> Int { 42 }
}

import Testing
@testable import Auth

struct LoginTests {
    // @use-case:shop.login.authenticate#unit-tests.valid-credentials
    @Test func validCredentialsAuthenticate() throws {
        let user = try LoginService().authenticate(username: "sam@example.com", password: "correct-password")
        #expect(user.id == "user-1")
    }
    // @use-case:end shop.login.authenticate#unit-tests.valid-credentials

    // @use-case:shop.login.authenticate#unit-tests.invalid-password
    @Test func invalidPasswordIsRejected() {
        #expect(throws: LoginError.invalidCredentials) {
            try LoginService().authenticate(username: "sam@example.com", password: "wrong")
        }
    }
    // @use-case:end shop.login.authenticate#unit-tests.invalid-password

    // @use-case:shop.login.lockout#unit-tests.three-failures
    @Test func lockedOutAfterThreeFailures() {
        let service = LoginService()
        for _ in 0..<3 { _ = try? service.authenticate(username: "sam@example.com", password: "wrong") }
        #expect(service.isLockedOut)
    }
    // @use-case:end shop.login.lockout#unit-tests.three-failures

    // @use-case:shop.login.password-reset#unit-tests.sends-reset
    @Test(.disabled("reset email service not wired yet"))
    func sendsResetEmail() {
        #expect(LoginService().sendReset(to: "sam@example.com"))
    }
    // @use-case:end shop.login.password-reset#unit-tests.sends-reset

    @Test func notTiedToAnyUseCase() {
        #expect(LoginService().unrelatedHelper() == 42)
    }
}

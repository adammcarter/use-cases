import Testing

struct LoginTests {
    // @use-case:shop.auth.login.authenticate#unit-tests.valid-credentials
    @Test
    func validCredentialsAuthenticate() throws {
        let service = LoginService()
        let user = try service.authenticate(
            username: "sam@example.com",
            password: "correct-password"
        )

        #expect(user.id == "user-1")
    }
    // @use-case:end shop.auth.login.authenticate#unit-tests.valid-credentials

    // @use-case:shop.auth.login.authenticate#unit-tests.invalid-password
    @Test
    func invalidPasswordIsRejected() {
        let service = LoginService()

        #expect(throws: LoginError.invalidCredentials) {
            try service.authenticate(
                username: "sam@example.com",
                password: "wrong-password"
            )
        }
    }
    // @use-case:end shop.auth.login.authenticate#unit-tests.invalid-password
}

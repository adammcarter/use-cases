struct User {
    let id: String
    let username: String
    let password: String
}

enum LoginError: Error {
    case invalidCredentials
}

final class UserStore {
    private let users: [User] = [
        User(id: "user-1", username: "sam@example.com", password: "correct-password")
    ]

    func find(_ username: String) -> User? {
        users.first { $0.username == username }
    }
}

final class LoginService {
    private let users = UserStore()

    // @use-case:shop.auth.login.authenticate#authenticate-request
    func authenticate(username: String, password: String) throws -> User {
        guard let user = users.find(username),
              user.password == password
        else {
            throw LoginError.invalidCredentials
        }

        return user
    }
    // @use-case:end shop.auth.login.authenticate#authenticate-request

    // The following block is intentionally also referenced by a manual binding.
    func recordSuccessfulLogin(for user: User) {
        let event = "login-success:\(user.id)"
        print(event)
    }
}

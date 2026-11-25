struct Order {
    let id: String
}

final class CheckoutService {
    func createOrder() async throws -> Order {
        Order(id: "ORDER-123")
    }
}

final class AppController {
    private let checkoutService = CheckoutService()
    private(set) var confirmationOrderID: String?

    // @use-case:shop.checkout.complete#checkout-entry
    func completeCheckout() async throws -> Order {
        let order = try await checkoutService.createOrder()
        confirmationOrderID = order.id
        return order
    }
    // @use-case:end shop.checkout.complete#checkout-entry
}

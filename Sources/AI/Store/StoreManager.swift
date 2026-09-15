import Foundation
import StoreKit

/// The real StoreKit 2 layer behind Premium.
///
/// Replaces the old local "Test Mode" toggle that just flipped
/// `PlayerProfile.isPremium` on tap. Everything here talks to the actual
/// App Store: the product is loaded from App Store Connect, the purchase
/// goes through Apple's sheet, and entitlement is read back from
/// `Transaction.currentEntitlements` rather than from anything we store
/// ourselves — so a lapsed, refunded or family-shared subscription is
/// always reflected correctly, including changes made on another device.
///
/// Premium is the subscription and nothing else — there is no Points
/// redemption path — so `isSubscribed` here is the single source of truth,
/// mirrored onto the profile by `PlayerState.refreshPremium(subscribed:)`.
@MainActor
final class StoreManager: ObservableObject {

    /// Must match the Product ID in App Store Connect exactly (subscription
    /// "Premium", group "Premium", Apple ID 6812364743). A mismatch surfaces
    /// as an empty product list with no error, not as a thrown failure.
    static let premiumProductID = "spaces_vip"

    /// Apple's standard EULA. App Review requires a reachable Terms of Use
    /// link on any screen that sells a subscription (Guideline 3.1.2); using
    /// Apple's standard agreement means there's nothing to self-host.
    static let termsOfUseURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    /// TODO: replace with the real published policy before submitting — App
    /// Store Connect also requires this exact URL in App Information.
    static let privacyPolicyURL = URL(string: "https://husseinalaa21.github.io/spaces_ai_game/privacy.html")!

    @Published private(set) var premiumProduct: Product?
    @Published private(set) var isSubscribed = false
    @Published private(set) var isLoadingProduct = false
    @Published private(set) var purchaseInFlight = false
    @Published private(set) var restoreInFlight = false

    /// Surfaced on the paywall when something goes wrong. A user-cancelled
    /// purchase is not an error and never sets this.
    @Published var errorMessage: String?

    private var updatesTask: Task<Void, Never>?

    init() {
        // Started before any purchase so transactions that complete outside
        // our own call site still land — Ask to Buy approvals, renewals, and
        // purchases made on the user's other devices.
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                await self.finish(result)
                await self.refreshEntitlement()
            }
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    // MARK: - Loading

    func loadProduct() async {
        guard premiumProduct == nil else { return }
        isLoadingProduct = true
        defer { isLoadingProduct = false }
        do {
            let products = try await Product.products(for: [StoreManager.premiumProductID])
            premiumProduct = products.first
            if premiumProduct == nil {
                // Almost always one of: the Paid Applications Agreement isn't
                // active, the product isn't "Ready to Submit", or the bundle
                // ID doesn't match the app record.
                errorMessage = "Premium isn't available right now. Please try again later."
            }
        } catch {
            errorMessage = "Couldn't reach the App Store. Check your connection and try again."
        }
    }

    // MARK: - Entitlement

    /// Reads Apple's own record of what this Apple ID currently owns.
    func refreshEntitlement() async {
        var active = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if transaction.productID == StoreManager.premiumProductID,
               transaction.revocationDate == nil {
                active = true
            }
        }
        isSubscribed = active
    }

    // MARK: - Purchase

    /// Returns true when the purchase completed and entitlement is now live.
    @discardableResult
    func purchasePremium() async -> Bool {
        guard let product = premiumProduct else {
            await loadProduct()
            guard premiumProduct != nil else { return false }
            return await purchasePremium()
        }
        guard !purchaseInFlight else { return false }
        purchaseInFlight = true
        defer { purchaseInFlight = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                await finish(verification)
                await refreshEntitlement()
                return isSubscribed
            case .userCancelled:
                return false
            case .pending:
                // Ask to Buy / SCA. The Transaction.updates listener above
                // picks it up if and when it's approved.
                errorMessage = "Your purchase is pending approval."
                return false
            @unknown default:
                return false
            }
        } catch {
            errorMessage = "The purchase couldn't be completed. Please try again."
            return false
        }
    }

    /// App Review requires a Restore Purchases control on any screen selling
    /// a subscription; this is what it calls.
    func restorePurchases() async {
        guard !restoreInFlight else { return }
        restoreInFlight = true
        defer { restoreInFlight = false }
        do {
            try await AppStore.sync()
            await refreshEntitlement()
            if !isSubscribed {
                errorMessage = "No previous Premium purchase was found for this Apple ID."
            }
        } catch {
            errorMessage = "Couldn't restore purchases. Please try again."
        }
    }

    private func finish(_ result: VerificationResult<Transaction>) async {
        // Unverified transactions failed Apple's own signature check — never
        // grant anything for them, and never finish them either.
        guard case .verified(let transaction) = result else { return }
        await transaction.finish()
    }

    // MARK: - Display

    /// Localized price straight from the product, so the UK sees £ and Japan
    /// sees ¥. Never hardcode this — a hardcoded "$9.99" is both wrong abroad
    /// and a Guideline 3.1.2 mismatch if the App Store Connect price changes.
    var displayPrice: String { premiumProduct?.displayPrice ?? "" }

    /// e.g. "month" / "year", taken from the subscription period.
    var periodLabel: String {
        guard let period = premiumProduct?.subscription?.subscriptionPeriod else { return "" }
        let unit: String
        switch period.unit {
        case .day: unit = "day"
        case .week: unit = "week"
        case .month: unit = "month"
        case .year: unit = "year"
        @unknown default: unit = "period"
        }
        return period.value > 1 ? "\(period.value) \(unit)s" : unit
    }

    /// Full button label, e.g. "Subscribe — $9.99/month".
    var subscribeTitle: String {
        guard premiumProduct != nil else { return "Subscribe" }
        return periodLabel.isEmpty ? "Subscribe — \(displayPrice)"
                                   : "Subscribe — \(displayPrice)/\(periodLabel)"
    }

    /// The auto-renew disclosure Apple requires next to the buy button.
    var renewalDisclosure: String {
        guard premiumProduct != nil, !periodLabel.isEmpty else {
            return "Payment is charged to your Apple Account. Subscriptions renew automatically until cancelled in Settings."
        }
        return "\(displayPrice) per \(periodLabel), charged to your Apple Account. Renews automatically until cancelled at least 24 hours before the end of the current period. Manage or cancel in Settings."
    }
}

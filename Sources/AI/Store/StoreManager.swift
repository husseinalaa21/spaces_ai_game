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

    /// App Review requires reachable Terms of Use and Privacy links on any
    /// screen that sells a subscription (Guideline 3.1.2). Both now point at
    /// the game's own published pages; the terms page links on to Apple's
    /// standard EULA, which governs the licence itself.
    ///
    /// Defined in `SpacesLinks` rather than here so the paywall, the Store,
    /// Settings and the About sheet can never drift apart.
    static var termsOfUseURL: URL { SpacesLinks.terms }
    static var privacyPolicyURL: URL { SpacesLinks.privacy }
    /// Apple's standard licence agreement — the EULA this app ships under,
    /// and the same address App Store Connect carries in the App Description.
    /// Shown by name next to the buy button so a reviewer can find it without
    /// having to open the game's own terms first.
    static var eulaURL: URL { SpacesLinks.appleEULA }

    /// Everything bought one at a time with real money (non-consumables, so Restore Purchases brings them back).
    /// Product IDs: `dot_<shape>` for a dot design, `universe_<look>` for a universe, `dots_customize` for Customize.
    static let shared = StoreManager()

    /// Set by the screen that owns the account: buying needs a signed-in account.
    var requiresSignIn: () -> Bool = { false }

    /// Consumable Point Packs, keyed by Product ID as registered in App Store Connect, mapped to the Points each credits.
    /// The Starter Pack's ID really is the string "0.99" — product IDs are permanent, so it must keep matching.
    static let pointPackGrants: [String: Int] = ["0.99": 500, "value": 3000, "mega": 12000]
    /// Credits Points for a consumable. Set once by the app so a transaction redelivered through `Transaction.updates`
    /// (after a crash, or an Ask to Buy approval) still pays out rather than being finished silently.
    var grantPoints: ((Int) -> Void)?
    @Published private(set) var pointPackProducts: [String: Product] = [:]
    /// Items bought with Points (kept on this device, like the Points themselves).
    @Published private(set) var pointsOwned: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "spaces.owned.withPoints") ?? [])

    @Published private(set) var goods: [String: Product] = [:]
    /// What this Apple ID owns of `StoreGoods`, read from Apple's entitlements and cached for offline use.
    @Published private(set) var owned: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "spaces.owned.goods") ?? [])

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
                await self.redeem(result)
                await self.refreshEntitlement()
            }
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    // MARK: - Loading

    func loadProduct() async {
        guard premiumProduct == nil || goods.isEmpty || pointPackProducts.isEmpty else { return }
        isLoadingProduct = true
        defer { isLoadingProduct = false }
        // A retry starts clean: without this, "Try Again" would keep showing
        // the failure it is trying to recover from even after it succeeds.
        errorMessage = nil
        do {
            let ids = Set([StoreManager.premiumProductID]).union(StoreGoods.allIDs).union(StoreManager.pointPackGrants.keys)
            let products = try await Product.products(for: ids)
            premiumProduct = products.first { $0.id == StoreManager.premiumProductID }
            goods = Dictionary(
                uniqueKeysWithValues: products
                    .filter { StoreGoods.allIDs.contains($0.id) }
                    .map { ($0.id, $0) }
            )
            pointPackProducts = Dictionary(
                uniqueKeysWithValues: products
                    .filter { StoreManager.pointPackGrants[$0.id] != nil }
                    .map { ($0.id, $0) }
            )
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
        var bought = Set<String>()
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result, transaction.revocationDate == nil else { continue }
            if transaction.productID == StoreManager.premiumProductID { active = true }
            if StoreGoods.allIDs.contains(transaction.productID) { bought.insert(transaction.productID) }
        }
        isSubscribed = active
        owned = bought
        UserDefaults.standard.set(Array(bought), forKey: "spaces.owned.goods")
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
                await redeem(verification)
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

    /// Members are people with an active Premium subscription.
    var isMember: Bool { isSubscribed }

    /// Whether the person can use this item: bought on its own, or Premium (which unlocks every look).
    func has(_ id: String) -> Bool { isSubscribed || owned.contains(id) || pointsOwned.contains(id) }

    /// Keeps an item that was paid for with Points.
    func unlockWithPoints(_ id: String) {
        pointsOwned.insert(id)
        UserDefaults.standard.set(Array(pointsOwned), forKey: "spaces.owned.withPoints")
    }

    /// Buys one consumable Point Pack. Points are credited by `redeem`, so the payout path is the same whether the
    /// transaction arrives here or is redelivered later by `Transaction.updates`.
    @discardableResult
    func purchasePointPack(id: String) async -> Bool {
        guard let product = pointPackProducts[id] else {
            errorMessage = "That pack isn't available right now."
            return false
        }
        guard !purchaseInFlight else { return false }
        purchaseInFlight = true
        defer { purchaseInFlight = false }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                await redeem(verification)
                return true
            case .userCancelled:
                return false
            case .pending:
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

    /// Buys one dot design, universe or Customize through Apple's purchase sheet.
    @discardableResult
    func purchase(goods id: String) async -> Bool {
        if goods[id] == nil { await loadProduct() }
        guard let product = goods[id] else {
            errorMessage = "That isn't available right now. Please try again later."
            return false
        }
        guard !purchaseInFlight else { return false }
        purchaseInFlight = true
        defer { purchaseInFlight = false }

        do {
            switch try await product.purchase() {
            case .success(let verification):
                await redeem(verification)
                await refreshEntitlement()
                return owned.contains(id)
            case .userCancelled:
                return false
            case .pending:
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

    /// Localized price of an item, or nil until its product loads.
    func price(for id: String) -> String? { (goods[id] ?? pointPackProducts[id])?.displayPrice }

    /// Closes out a verified transaction. Unverified ones failed Apple's own signature check and are never finished or granted.
    private func redeem(_ result: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = result else { return }
        // A consumable is finished only AFTER its Points are delivered, or a crash in between would lose the purchase.
        if transaction.revocationDate == nil, let points = StoreManager.pointPackGrants[transaction.productID] {
            grantPoints?(points)
        }
        await transaction.finish()
    }

    // MARK: - Display

    /// Localized price straight from the product, so the UK sees £ and Japan
    /// sees ¥. Never hardcode this — a hardcoded "$9.99" is both wrong abroad
    /// and a Guideline 3.1.2 mismatch if the App Store Connect price changes.
    var displayPrice: String { premiumProduct?.displayPrice ?? "" }

    /// The subscription's own title as App Store Connect localizes it, which
    /// is what Guideline 3.1.2(c) means by "title of auto-renewing
    /// subscription". Falls back to the product's reference name until the
    /// product has loaded.
    var premiumTitle: String { premiumProduct?.displayName ?? "Premium" }

    private var periodUnit: String {
        guard let period = premiumProduct?.subscription?.subscriptionPeriod else { return "" }
        switch period.unit {
        case .day: return "day"
        case .week: return "week"
        case .month: return "month"
        case .year: return "year"
        @unknown default: return "period"
        }
    }

    /// e.g. "month" / "year", taken from the subscription period.
    var periodLabel: String {
        guard let period = premiumProduct?.subscription?.subscriptionPeriod else { return "" }
        return period.value > 1 ? "\(period.value) \(periodUnit)s" : periodUnit
    }

    /// The length of one billing period spelled out — "1 month" — for the
    /// "Length of subscription" line Guideline 3.1.2(c) requires. Unlike
    /// `periodLabel` it always carries the count.
    var lengthLabel: String {
        guard let period = premiumProduct?.subscription?.subscriptionPeriod else { return "" }
        return "\(period.value) \(periodUnit)\(period.value > 1 ? "s" : "")"
    }

    /// e.g. "$9.99 per month" — price and unit together, straight from the
    /// product so it is always the App Store Connect price for this storefront.
    var priceSummary: String {
        guard premiumProduct != nil, !periodLabel.isEmpty else { return "" }
        return "\(displayPrice) per \(periodLabel)"
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
        return "\(displayPrice) per \(periodLabel), charged to your Apple Account at confirmation of purchase. The subscription renews automatically for the same price and length unless it is cancelled at least 24 hours before the end of the current period, and your account is charged for renewal within 24 hours before that period ends. Manage or cancel any time in your Apple Account settings."
    }
}

/// What the Store sells.
enum StoreGoods {
    static let customizeID = "dots_customize"
    static let paidUniverses: [UniverseTheme] = UniverseTheme.allCases.filter { $0 != .white }
    static let paidThemes: [DotTheme] = DotTheme.allCases.filter { $0 != .classic }

    static func themeID(_ theme: DotTheme) -> String { "dottheme_" + theme.rawValue }
    static func universeID(_ theme: UniverseTheme) -> String { "universe_" + theme.rawValue }

    /// What an item costs in Points instead of money.
    static let themePoints = 3000
    static let universePoints = 1200

    static var allIDs: Set<String> {
        Set(paidThemes.map(themeID)).union(paidUniverses.map(universeID)).union([customizeID])
    }
}

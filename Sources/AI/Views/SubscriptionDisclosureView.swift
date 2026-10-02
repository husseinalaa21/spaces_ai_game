import SwiftUI

/// What App Review's Guideline 3.1.2(c) requires beside the buy button of an
/// auto-renewing subscription, in one place so every screen that sells
/// Premium shows exactly the same thing:
///
/// - the subscription's title,
/// - its length,
/// - its price (and price per unit),
/// - functional links to the Terms of Use (EULA) and the Privacy Policy.
///
/// `SubscriptionSummaryView` covers the first three, taken from the loaded
/// StoreKit product rather than typed in, so it can never disagree with App
/// Store Connect. `SubscriptionLegalLinks` covers the last.
struct SubscriptionSummaryView: View {
    @ObservedObject var store: StoreManager

    var body: some View {
        VStack(spacing: 0) {
            row("Subscription", store.premiumTitle)
            Divider()
            row("Length", "\(store.lengthLabel), renews automatically")
            Divider()
            row("Price", store.priceSummary)
        }
        .padding(.horizontal, 14)
        .background(Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.black.opacity(0.5))
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.black.opacity(0.85))
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 10)
    }
}

/// "Terms of Use · EULA · Privacy Policy".
///
/// Terms of Use is the game's own page, which states that Apple's standard
/// licence applies; EULA is Apple's standard licence itself — the same
/// address the App Description carries — so a reviewer can reach either from
/// the paywall. All three come from `SpacesLinks` through `StoreManager`.
struct SubscriptionLegalLinks: View {
    var body: some View {
        HStack(spacing: 10) {
            Link("Terms of Use", destination: StoreManager.termsOfUseURL)
            separator
            Link("EULA", destination: StoreManager.eulaURL)
            separator
            Link("Privacy Policy", destination: StoreManager.privacyPolicyURL)
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundColor(.black.opacity(0.6))
    }

    private var separator: some View {
        Text("·").foregroundColor(.black.opacity(0.3))
    }
}

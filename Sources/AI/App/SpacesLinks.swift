import Foundation

/// Every web address the app links to, in one place.
///
/// Scattering literal URLs through the views is how a link quietly rots:
/// the privacy policy alone is referenced from the paywall, the Store, the
/// Settings page and the About sheet, and App Store Connect needs the exact
/// same string in App Information. One constant means one thing to change.
///
/// ## Moving to a custom domain
///
/// `base` is the only line to edit. Point it at `https://spaces.spacechat.app`
/// (or any host you own), add a matching `CNAME` file to `docs/`, and set the
/// DNS record — every link below follows automatically, and no view changes.
enum SpacesLinks {

    /// Where the site is served from. GitHub Pages publishes `docs/` on the
    /// default branch at exactly this path.
    static let base = URL(string: "https://husseinalaa21.github.io/spaces_ai_game")!

    static var home: URL { base.appendingPathComponent("index.html") }
    static var pricing: URL { base.appendingPathComponent("pricing.html") }
    static var membership: URL { base.appendingPathComponent("membership.html") }
    static var blog: URL { base.appendingPathComponent("blog.html") }
    static var privacy: URL { base.appendingPathComponent("privacy.html") }
    static var terms: URL { base.appendingPathComponent("terms.html") }
    static var support: URL { base.appendingPathComponent("support.html") }

    /// Spacechat itself — the account system behind the game.
    static let spacechat = URL(string: "https://www.spacechat.app")!

    /// Apple's standard licence, which `terms` also links to. Kept separate
    /// because Apple's own agreement governs the licence itself, whatever the
    /// game's terms say.
    static let appleEULA = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    /// Apple's refund flow. Refunds are entirely Apple's to grant, so the app
    /// should send people there rather than to us.
    static let refunds = URL(string: "https://reportaproblem.apple.com")!

    /// Apple's subscription management page — the fallback when StoreKit's
    /// in-app manage sheet is unavailable.
    static let manageSubscriptions = URL(string: "https://apps.apple.com/account/subscriptions")!

    static let supportEmail = "hussein.scs@gmail.com"
}

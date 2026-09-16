import Foundation

/// Every web address the app links to, in one place.
///
/// Scattering literal URLs through the views is how a link quietly rots:
/// the privacy policy alone is referenced from the paywall, the Store, the
/// Settings page and the About sheet, and App Store Connect needs the exact
/// same string in App Information. One constant means one thing to change.
///
/// ## Where these are served
///
/// The Spacechat server itself, from its `spaces/` directory — see the
/// `/spaces` routes in `server.js`. That keeps every address the game shows
/// on spacechat.app rather than on a separate host.
///
/// `base` is the only line that names a host. Nothing below, and no view,
/// refers to one.
enum SpacesLinks {

    static let base = URL(string: "https://www.spacechat.app/spaces")!

    /// Extensionless on purpose: the server maps a bare page name to its
    /// `.html` file, so these read as addresses rather than as files.
    static var home: URL { base }
    static var pricing: URL { base.appendingPathComponent("pricing") }
    static var membership: URL { base.appendingPathComponent("membership") }
    static var blog: URL { base.appendingPathComponent("blog") }
    static var privacy: URL { base.appendingPathComponent("privacy") }
    static var terms: URL { base.appendingPathComponent("terms") }
    static var support: URL { base.appendingPathComponent("support") }

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

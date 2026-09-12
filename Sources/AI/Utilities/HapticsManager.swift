import UIKit

/// Thin wrapper so the rest of the app never touches UIKit haptics directly
/// (§53: light haptics for eating, form completion, abilities — never constant).
final class HapticsManager {
    static let shared = HapticsManager()
    var isEnabled = true

    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    private let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    private let notification = UINotificationFeedbackGenerator()

    private init() {}

    func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        guard isEnabled else { return }
        switch style {
        case .light: impactLight.impactOccurred()
        case .medium: impactMedium.impactOccurred()
        default: impactMedium.impactOccurred()
        }
    }

    func success() {
        guard isEnabled else { return }
        notification.notificationOccurred(.success)
    }
}

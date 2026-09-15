import SwiftUI
import StoreKit
import UIKit
import UniformTypeIdentifiers

/// Shows the recovery phrase for a Spacechat account, from the Keychain.
///
/// Hidden until deliberately revealed: this is the whole account, and a
/// settings screen is exactly where someone opens the app in public.
struct RecoveryPhraseSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var revealed = false
    @State private var copied = false
    @State private var showExporter = false

    private var phrase: String { SpacechatAuth.storedPhrase() ?? "" }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Label("Anyone with these words can sign in as you. Spacechat will never ask you for them.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.orange)

                    ZStack {
                        Text(phrase)
                            .font(.system(size: 15, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .opacity(revealed ? 1 : 0)
                        if !revealed {
                            Text("Tap Show words to reveal")
                                .font(.system(size: 13))
                                .foregroundColor(.black.opacity(0.4))
                                .padding(14)
                        }
                    }
                    .frame(minHeight: 108, alignment: .topLeading)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 12))

                    HStack(spacing: 10) {
                        action(revealed ? "Hide" : "Show words",
                               icon: revealed ? "eye.slash.fill" : "eye.fill") {
                            revealed.toggle()
                        }
                        action(copied ? "Copied" : "Copy", icon: copied ? "checkmark" : "doc.on.doc") {
                            UIPasteboard.general.string = phrase
                            copied = true
                        }
                        action("Save", icon: "square.and.arrow.down") { showExporter = true }
                    }

                    Text("Stored in this device's Keychain, marked so it never leaves in an iCloud or iTunes backup.")
                        .font(.system(size: 11))
                        .foregroundColor(.black.opacity(0.4))
                }
                .padding(20)
            }
            .background(Color(white: 0.97).ignoresSafeArea())
            .navigationTitle("Recovery Phrase")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .fileExporter(isPresented: $showExporter,
                          document: PhraseFile(text: phrase),
                          contentType: .plainText,
                          defaultFilename: "spacechat-recovery-phrase") { _ in }
        }
    }

    private func action(_ title: String, icon: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Label(title, systemImage: icon)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
        }
        .foregroundColor(.black)
        .background(Color.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        .buttonStyle(.plain)
    }
}

private struct PhraseFile: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws {
        text = String(data: configuration.file.regularFileContents ?? Data(), encoding: .utf8) ?? ""
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

/// Everything this Apple Account has bought in the app, read from StoreKit.
///
/// Apple is the record of truth for purchases, so this reads
/// `Transaction.all` rather than anything the app stored — which also means
/// it is correct on a fresh install with no local history at all.
struct PurchaseHistoryView: View {
    @ObservedObject var store: StoreManager
    @Environment(\.dismiss) private var dismiss

    private struct Entry: Identifiable {
        let id: UInt64
        let productID: String
        let date: Date
        let isRefunded: Bool
        let isSubscription: Bool
    }

    @State private var entries: [Entry] = []
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if entries.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 30))
                            .foregroundColor(.black.opacity(0.25))
                        Text("No purchases yet")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                        Text("Anything you buy will show up here, tied to your Apple Account.")
                            .font(.system(size: 12))
                            .foregroundColor(.black.opacity(0.5))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(entries) { entry in
                                row(entry)
                                if entry.id != entries.last?.id { Divider().padding(.leading, 14) }
                            }
                        }
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
                        .padding(16)
                    }
                }
            }
            .background(Color(white: 0.97).ignoresSafeArea())
            .navigationTitle("Purchase History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .task { await load() }
        }
    }

    private func row(_ entry: Entry) -> some View {
        HStack(spacing: 12) {
            Image(systemName: entry.isSubscription ? "star.circle.fill" : "sparkles")
                .font(.system(size: 16))
                .foregroundColor(entry.isRefunded ? .black.opacity(0.3) : .black.opacity(0.7))
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName(for: entry.productID))
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 12))
                    .foregroundColor(.black.opacity(0.5))
            }
            Spacer()
            if entry.isRefunded {
                Text("Refunded")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.black.opacity(0.4))
            }
        }
        .padding(14)
    }

    /// Product IDs are not customer-facing strings — "0.99" in particular
    /// would be baffling in a purchase list.
    private func displayName(for productID: String) -> String {
        switch productID {
        case StoreManager.premiumProductID: return "Premium"
        case "0.99": return "Starter Pack — 500 Points"
        case "value": return "Value Pack — 3,000 Points"
        case "mega": return "Mega Pack — 12,000 Points"
        default: return productID
        }
    }

    private func load() async {
        var found: [Entry] = []
        for await result in Transaction.all {
            guard case .verified(let transaction) = result else { continue }
            found.append(Entry(
                id: transaction.id,
                productID: transaction.productID,
                date: transaction.purchaseDate,
                isRefunded: transaction.revocationDate != nil,
                isSubscription: transaction.productID == StoreManager.premiumProductID
            ))
        }
        entries = found.sorted { $0.date > $1.date }
        isLoading = false
    }
}

/// Plain explanation of what Spacechat is and how the game relates to it.
struct AboutSpacechatView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 10) {
                        SpacechatMark(size: 34)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Spacechat")
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                            Text("Spacechat LLC")
                                .font(.system(size: 12))
                                .foregroundColor(.black.opacity(0.5))
                        }
                    }

                    paragraph("Spacechat is private chat and voice without an email address, a phone number, a wallet, or a social login. An account is a recovery phrase — twelve to eighteen words that you hold and nobody else can reissue.")

                    paragraph("This game uses the same accounts. Signing in with your phrase here signs you into the same Spacechat account, so Messages and Spacechat AI in the game are the same conversations you would see in the Spacechat app.")

                    paragraph("Because the phrase is the account, it is stored in this device's Keychain and marked so it never travels in a backup, and signing out removes it from this device entirely.")

                    Divider()

                    VStack(alignment: .leading, spacing: 10) {
                        Link(destination: URL(string: "https://www.spacechat.app")!) {
                            Label("spacechat.app", systemImage: "globe")
                        }
                        Link(destination: StoreManager.privacyPolicyURL) {
                            Label("Privacy Policy", systemImage: "hand.raised")
                        }
                        Link(destination: StoreManager.termsOfUseURL) {
                            Label("Terms of Use", systemImage: "doc.text")
                        }
                    }
                    .font(.system(size: 14, weight: .medium))
                }
                .padding(20)
            }
            .background(Color(white: 0.97).ignoresSafeArea())
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private func paragraph(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14))
            .foregroundColor(.black.opacity(0.75))
            .fixedSize(horizontal: false, vertical: true)
    }
}

import SwiftUI
import StoreKit
import UIKit
import UniformTypeIdentifiers
import AuthenticationServices
import PhotosUI

/// Shows the recovery phrase for a Spacechat account, from the Keychain.
///
/// Hidden until deliberately revealed: this is the whole account, and a
/// settings screen is exactly where someone opens the app in public.
struct RecoveryPhraseSheet: View {
    var firstLogin = false
    var onContinue: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
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

                    if phrase.isEmpty {
                        Text("This account was opened through Apple or Google. Use the recovery phrase you saved when creating it; Spacechat cannot retrieve the original words. You can continue using your connected provider.")
                            .font(.system(size: 14))
                    }

                    ZStack {
                        Text(phrase)
                            .accessibilityHidden(!revealed)
                            .privacySensitive()
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

                    .disabled(phrase.isEmpty)

                    if firstLogin {
                        Button("Continue") { onContinue?() }
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity).padding(14)
                            .background(Color.black, in: RoundedRectangle(cornerRadius: 14))
                    }

                    Text("Stored in this device's Keychain, marked so it never leaves in an iCloud or iTunes backup.")
                        .font(.system(size: 11))
                        .foregroundColor(.black.opacity(0.4))
                }
                .padding(20)
            }
            .background(Color(white: 0.97).ignoresSafeArea())
            .onChange(of: scenePhase) { phase in if phase != .active { revealed = false } }
            .navigationTitle("Recovery Phrase")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    if !firstLogin { Button("Done") { dismiss() } }
                }
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
    static var readableContentTypes: [UTType] { [.plainText, .json] }
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

                    paragraph("This app uses the same accounts and the same servers. Signing in with your phrase here signs you into your Spacechat account, so Messages and Spacechat AI here reach the same people and the same Spacechat AI as the Spacechat app. Each device keeps its own conversation history, so older chats stay in the app where you had them.")

                    paragraph("Because the phrase is the account, it is stored in this device's Keychain and marked so it never travels in a backup, and signing out removes it from this device entirely.")

                    Divider()

                    VStack(alignment: .leading, spacing: 10) {
                        Link(destination: SpacesLinks.home) {
                            Label("The Space - Dots & AI site", systemImage: "globe")
                        }
                        Link(destination: SpacesLinks.spacechat) {
                            Label("spacechat.app", systemImage: "network")
                        }
                        Link(destination: SpacesLinks.privacy) {
                            Label("Privacy Policy", systemImage: "hand.raised")
                        }
                        Link(destination: SpacesLinks.terms) {
                            Label("Terms of Use", systemImage: "doc.text")
                        }
                        Link(destination: SpacesLinks.appleEULA) {
                            Label("License Agreement (EULA)", systemImage: "doc.plaintext")
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

/// Shared account behavior from Spacechat Settings/Account/Profile, presented
/// using this app's native grouped settings style and the same server APIs.
struct SharedAccountSettingsView: View {
    @ObservedObject var player: PlayerState
    @ObservedObject var authState: AuthState
    @ObservedObject var sync: SpacechatSync
    var save: () -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var googleSignIn = GameGoogleSignIn()
    @State private var email = ""
    @State private var emailCode = ""
    @State private var emailCodeSent = false
    @State private var name = ""
    @State private var bio = ""
    @State private var username = ""
    @State private var avatarBackground = "auto"
    @State private var profileTheme = "orbit"
    @State private var storage = "browser"
    @State private var photo: PhotosPickerItem?
    @State private var pictureDataURL: String?
    @State private var removePicture = false
    @State private var busy = false
    @State private var notice = ""
    @State private var error = ""
    @State private var showPhrase = false
    @State private var showImport = false
    @State private var showExport = false
    @State private var includePhrase = false
    @State private var exportText = ""
    @State private var pendingImport: [String: Any]?
    @State private var showRestore = false
    @State private var showReload = false
    @State private var showDelete = false
    @State private var deleteText = ""
    @State private var googleClientID = ""
    @State private var connectedProviders: Set<String> = []
    @State private var disconnectProvider: String?

    var body: some View {
        NavigationStack {
            Form {
                identitySection
                emailSection
                profileSection
                recoverySection
                providerSection
                storageSection
                backupSection
                Section("Delete account") {
                    Text("Permanently deletes this shared account in both apps, including its cloud data. App Store subscriptions are managed separately.")
                        .font(.footnote).foregroundColor(.secondary)
                    Button("Delete shared account", role: .destructive) { showDelete = true }
                }
                if !notice.isEmpty { Section { Text(notice).foregroundColor(.green) } }
                if !error.isEmpty { Section { Text(error).foregroundColor(.red) } }
                if busy { Section { ProgressView("Working…") } }
            }
            .disabled(busy)
            .navigationTitle("Spacechat Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { await loadAccount() }
            .sheet(isPresented: $showPhrase) { RecoveryPhraseSheet() }
            .fileExporter(isPresented: $showExport, document: PhraseFile(text: exportText), contentType: .json,
                          defaultFilename: "spacechat-account-database") { result in
                if case .failure = result { error = "Couldn't export that file. Try again." }
                exportText = ""
            }
            .fileImporter(isPresented: $showImport, allowedContentTypes: [.json], allowsMultipleSelection: false, onCompletion: readImport)
            .confirmationDialog("Restore game progress from this file?", isPresented: $showRestore, titleVisibility: .visible) {
                Button("Restore game progress", role: .destructive) { restoreImport() }
                Button("Cancel", role: .cancel) { pendingImport = nil }
            } message: { Text("This replaces this account's game progress on this device. Cloud data changes only when you choose Save to cloud.") }
            .confirmationDialog("Replace device progress with the cloud save?", isPresented: $showReload, titleVisibility: .visible) {
                Button("Reload cloud progress", role: .destructive) {
                    perform {
                        guard await sync.refresh() else { throw SpacechatAuth.AuthError.rejected("Couldn't load cloud progress. Check the storage status and try again.") }
                        guard let cloud = sync.cloudProfile() else { throw SpacechatAuth.AuthError.rejected("This account has no cloud game save yet.") }
                        player.profile = cloud; sync.confirmLoadedProfile(cloud); save(); notice = "Cloud progress restored."
                    }
                }
            }
            .alert("Delete this shared account?", isPresented: $showDelete) {
                TextField("Type DELETE", text: $deleteText)
                    .textInputAutocapitalization(.characters).autocorrectionDisabled()
                Button("Cancel", role: .cancel) { deleteText = "" }
                Button("Delete", role: .destructive) {
                    guard deleteText == "DELETE" else { error = "Type DELETE to confirm account deletion."; return }
                    perform {
                        let json = try await SpacechatService.post("account/delete", body: ["confirm": "DELETE"])
                        guard json["deleted"] as? Bool == true else { throw SpacechatAuth.AuthError.rejected("The account was not deleted. Try again.") }
                        if let username = authState.spacechatUsername {
                            SpacesInbox.removeLocalAccountData(username: username)
                            SpacesAIStore.removeLocalAccountData(username: username)
                        }
                        sync.disconnect(); authState.finishAccountDeletion(); dismiss()
                    }
                }
            } message: { Text("This affects Spacechat and Space – Dots & AI. Type DELETE to confirm.") }
            .confirmationDialog("Disconnect this login option?", isPresented: Binding(get: { disconnectProvider != nil }, set: { if !$0 { disconnectProvider = nil } }), titleVisibility: .visible) {
                Button("Disconnect", role: .destructive) {
                    guard let provider = disconnectProvider else { return }
                    disconnectProvider = nil
                    perform {
                        _ = try await SpacechatService.post("auth/social/unlink", body: ["provider": provider])
                        await loadAccount(); notice = "Login option disconnected."
                    }
                }
            } message: { Text("Keep your recovery phrase before disconnecting. Removing the last provider may turn off free cloud storage.") }
            .onChange(of: photo) { item in
                guard let item else { return }
                perform {
                    guard let data = try await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
                        throw SpacechatAuth.AuthError.rejected("Couldn't read that photo.")
                    }
                    let format = UIGraphicsImageRendererFormat(); format.scale = 1
                    let renderer = UIGraphicsImageRenderer(size: CGSize(width: 512, height: 512), format: format)
                    let square = renderer.image { _ in
                        let scale = max(512 / image.size.width, 512 / image.size.height)
                        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                        image.draw(in: CGRect(x: (512 - size.width) / 2, y: (512 - size.height) / 2, width: size.width, height: size.height))
                    }
                    guard let encoded = square.jpegData(compressionQuality: 0.8) else { return }
                    pictureDataURL = "data:image/jpeg;base64," + encoded.base64EncodedString(); removePicture = false
                    notice = "Photo ready. Tap Save profile to upload it."
                }
            }
        }
    }

    private var identitySection: some View {
        Section("Identity") {
            LabeledContent("Username", value: authState.spacechatUsername ?? "")
            LabeledContent("Private username", value: authState.lastAccount?.privateUsername ?? "")
            LabeledContent("Reference ID", value: authState.lastAccount?.referenceID ?? "")
            Text("This is the same account used by Spacechat. Your recovery phrase opens it in either app.")
                .font(.footnote).foregroundColor(.secondary)
            Button("Refresh from server") { perform { await loadAccount() } }
        }
    }

    private var emailSection: some View {
        Section("Account email") {
            TextField("Email address", text: $email)
                .keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
            Text(authState.lastAccount?.details["emailVerified"] as? Bool == true ? "Verified" : "Not verified")
                .font(.footnote).foregroundColor(.secondary)
            Button("Send verification code") {
                perform {
                    _ = try await SpacechatService.post("profile/email/request-code", body: ["email": email])
                    emailCodeSent = true; notice = "Verification code sent. Check your inbox."
                }
            }
            if emailCodeSent {
                TextField("Six-digit code", text: $emailCode).keyboardType(.numberPad)
                Button("Verify email") {
                    perform {
                        _ = try await SpacechatService.post("profile/email/verify-code", body: ["code": emailCode])
                        emailCode = ""; emailCodeSent = false
                        try await authState.refreshAccount(); notice = "Email verified."
                    }
                }
            }
            Button("Remove account email", role: .destructive) {
                perform {
                    _ = try await SpacechatService.post("profile/email/delete")
                    email = ""; emailCode = ""; emailCodeSent = false
                    try await authState.refreshAccount(); notice = "Email removed."
                }
            }
        }
    }

    private var profileSection: some View {
        Section("Shared profile") {
            TextField("Display name", text: $name)
            TextField("Bio", text: $bio, axis: .vertical).lineLimit(2...5)
            if let url = URL(string: authState.lastAccount?.picture ?? ""), pictureDataURL == nil && !removePicture {
                AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { Color.gray.opacity(0.1) }
                    .frame(width: 64, height: 64).clipShape(Circle()).accessibilityLabel("Profile photo")
            }
            PhotosPicker("Choose profile photo", selection: $photo, matching: .images)
            Button("Remove custom photo") { pictureDataURL = nil; removePicture = true }
            Button("Save profile") {
                perform {
                    var body: [String: Any] = ["name": name, "description": bio, "avatarBackground": avatarBackground, "profileTheme": profileTheme]
                    if let pictureDataURL { body["pictureDataUrl"] = pictureDataURL }
                    if removePicture { body["removeCustomPicture"] = true }
                    let result = try await SpacechatService.post("profile/update", body: body)
                    try await authState.refreshAccount()
                    pictureDataURL = nil; removePicture = false
                    notice = result["publicSyncPending"] as? Bool == true ? "Profile saved. Public directory sync is pending; refresh later." : "Profile saved to your shared Spacechat account."
                }
            }
            TextField("Public username", text: $username).textInputAutocapitalization(.never).autocorrectionDisabled()
            Button("Update username") {
                perform {
                    _ = try await SpacechatService.post("username/set", body: ["username": username])
                    try await authState.refreshAccount(); notice = "Username updated."
                }
            }
        }
    }

    private var recoverySection: some View {
        Section("Recovery phrase") {
            Button("View, copy or download recovery phrase") { showPhrase = true }
            Text("New accounts use 12 words. Existing Spacechat phrases with 12–18 words also work.")
                .font(.footnote).foregroundColor(.secondary)
        }
    }

    private var providerSection: some View {
        Section("Connected login options") {
            ForEach(["apple", "google"], id: \.self) { provider in
                if connectedProviders.contains(provider) {
                    Button("Disconnect " + provider.capitalized, role: .destructive) { disconnectProvider = provider }
                }
            }
            SignInWithAppleButton(.continue) { $0.requestedScopes = [.email] } onCompletion: { result in
                if case .success(let authorization) = result,
                   let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                   let data = credential.identityToken, let token = String(data: data, encoding: .utf8) {
                    let code = credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                    connect(provider: "apple", token: token, code: code)
                } else if case .failure(let failure) = result, (failure as? ASAuthorizationError)?.code != .canceled {
                    error = "Apple connection did not finish. Try again."
                }
            }
            .signInWithAppleButtonStyle(.black).frame(height: 44)
            if !googleClientID.isEmpty {
                Button("Connect Google") {
                    perform {
                        let token = try await googleSignIn.identityToken(clientId: googleClientID)
                        _ = try await SpacechatService.post("auth/social/link", body: ["provider": "google", "idToken": token])
                        await loadAccount(); notice = "Google connected to this account."
                    }
                }
            }
            Text("Connecting a provider here keeps your current account. If it already belongs to another account, the server asks you to sign in to that account instead.")
                .font(.footnote).foregroundColor(.secondary)
        }
    }

    private var storageSection: some View {
        Section("Storage & database") {
            Picker("Save account data", selection: $storage) {
                Text("This device").tag("browser")
                Text("Cloud").tag("prepaid")
                Text("No cloud storage").tag("none")
            }
            Button("Apply storage choice") {
                perform {
                    if storage == "prepaid" && !sync.cloudAvailable {
                        throw SpacechatAuth.AuthError.rejected("Connect Apple or Google, or activate Spacechat cloud storage, before choosing cloud.")
                    }
                    let json = try await SpacechatService.post("session/database-mode", body: ["databaseMode": storage])
                    if let token = json["sessionToken"] as? String, !token.isEmpty { SpacechatAuth.storeSession(token) }
                    SpacechatAuth.preferredDatabaseMode = storage
                    try await authState.refreshAccount()
                    if let account = authState.lastAccount { sync.adopt(account) }
                    notice = "Storage preference saved."
                }
            }
            Text(storageStatus).font(.footnote).foregroundColor(.secondary)
            if let date = sync.lastSyncedAt { LabeledContent("Last cloud save", value: date.formatted()) }
            Button("Save game progress to cloud") {
                perform {
                    await sync.push(player.profile, replaceCloud: true)
                    if case .failed(let reason) = sync.state { throw SpacechatAuth.AuthError.rejected(reason) }
                    guard sync.state == .ready else { throw SpacechatAuth.AuthError.rejected("Choose available cloud storage first.") }
                    notice = "Game progress saved to cloud."
                }
            }
            Button("Reload game progress from cloud") { showReload = true }
        }
    }

    private var backupSection: some View {
        Section("Database backup") {
            Toggle("Include recovery phrase in export", isOn: $includePhrase)
                .disabled(SpacechatAuth.storedPhrase() == nil)
            Text("A file containing your phrase gives access to your account. Keep it private. Imported progress is restored only into its matching account.")
                .font(.footnote).foregroundColor(.secondary)
            Button("Download account database") {
                perform {
                    guard let account = authState.lastAccount else { throw SpacechatAuth.AuthError.rejected("Refresh your account first.") }
                    var database = account.database ?? [:]
                    let raw = try JSONSerialization.jsonObject(with: JSONEncoder().encode(player.profile))
                    database["spacesDotsGame"] = ["profile": raw, "updatedAt": Date().timeIntervalSince1970 * 1000]
                    database["username"] = account.username; database["privateUsername"] = account.privateUsername; database["referenceId"] = account.referenceID
                    var bundle: [String: Any] = ["app": "spacechat", "kind": "spacechat-account-database", "version": 1, "exportedAt": Date().timeIntervalSince1970 * 1000, "username": account.username, "privateUsername": account.privateUsername, "referenceId": account.referenceID, "localDatabase": database]
                    if includePhrase { bundle["passphrase"] = SpacechatAuth.storedPhrase() ?? "" }
                    exportText = String(data: try JSONSerialization.data(withJSONObject: bundle, options: [.prettyPrinted, .sortedKeys]), encoding: .utf8) ?? ""
                    showExport = true
                }
            }
            Button("Upload account database") { showImport = true }
        }
    }

    private var storageStatus: String {
        switch sync.state {
        case .signedOut: return "Sign in to sync."
        case .localOnly: return "Game progress is saved on this device. Cloud sync is off."
        case .ready: return "Cloud storage is ready."
        case .syncing: return "Syncing…"
        case .failed(let message): return message
        }
    }

    @MainActor private func perform(_ operation: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        busy = true; error = ""; notice = ""
        Task {
            defer { busy = false }
            do { try await operation() }
            catch is CancellationError { }
            catch { self.error = error.localizedDescription }
        }
    }

    @MainActor private func loadAccount() async {
        do {
            try await authState.refreshAccount()
            if let account = authState.lastAccount {
                email = account.details["email"] as? String ?? ""
                name = account.details["name"] as? String ?? ""; bio = account.description; username = account.username
                avatarBackground = account.details["avatarBackground"] as? String ?? "auto"
                profileTheme = account.details["profileTheme"] as? String ?? "orbit"
                storage = account.databaseMode; sync.adopt(account)
            }
            let links = try await SpacechatService.post("auth/social/status")
            let providers = links["socialLogins"] as? [String: [String: Any]] ?? [:]
            connectedProviders = Set(providers.filter { $0.value["connected"] as? Bool == true }.map(\.key))
            if let config = try? await SpacechatAuth.request("auth/social/config", body: ["nativeApp": "spaces"]),
               let google = config["google"] as? [String: Any], config["nativeApp"] as? String == "spaces", google["iosEnabled"] as? Bool == true {
                googleClientID = google["iosClientId"] as? String ?? ""
            }
        } catch { self.error = error.localizedDescription }
    }

    private func connect(provider: String, token: String, code: String) {
        perform {
            _ = try await SpacechatService.post("auth/social/link", body: ["provider": provider, "idToken": token, "authorizationCode": code])
            await loadAccount(); notice = provider.capitalized + " connected to this account."
        }
    }

    private func readImport(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            guard let url = urls.first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 4_000_000 else {
                throw SpacechatAuth.AuthError.rejected("This backup exceeds the 4 MB import limit.")
            }
            let text = try String(contentsOf: url, encoding: .utf8)
            guard let object = SpacechatBackup.object(from: text), let account = authState.lastAccount,
                  SpacechatBackup.owns(object, account: account) else {
                throw SpacechatAuth.AuthError.rejected("This is not a database backup for the signed-in account.")
            }
            let database = SpacechatBackup.database(from: object)
            guard let game = database["spacesDotsGame"] as? [String: Any], game["profile"] is [String: Any] else {
                throw SpacechatAuth.AuthError.rejected("This account backup does not contain Space – Dots & AI game progress.")
            }
            pendingImport = object; showRestore = true
        } catch { self.error = error.localizedDescription }
    }

    private func restoreImport() {
        guard let object = pendingImport, let account = authState.lastAccount, SpacechatBackup.owns(object, account: account) else { return }
        perform {
            let database = SpacechatBackup.database(from: object)
            guard let game = database["spacesDotsGame"] as? [String: Any], let raw = game["profile"] as? [String: Any] else { return }
            player.profile = try JSONDecoder().decode(PlayerProfile.self, from: JSONSerialization.data(withJSONObject: raw))
            save(); pendingImport = nil; notice = "Game progress restored to this device."
        }
    }
}

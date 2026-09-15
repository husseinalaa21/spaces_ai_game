import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Signing in with a Spacechat recovery phrase — the second route offered
/// under Sign in with Apple.
///
/// Structured the same way the Spacechat client is (see `NativeLoginView`'s
/// `NativeLoginPhraseMode`, which mirrors the web client's
/// `auth_phrase_choice`): a chooser of three routes first, then the phrase
/// editor. Upload and Type both land in `.type`; Create lands in `.create`
/// pre-filled with a freshly generated phrase and the extra affordances that
/// matter only when a phrase is brand new — regenerate, copy, save to Files,
/// and the warning that nobody can recover it for you.
///
/// There is no separate sign-up call: the server creates the account when it
/// doesn't recognize the phrase, which is what makes Create a login.
struct SpacechatPhraseView: View {
    @ObservedObject var authState: AuthState
    var onSignedIn: () -> Void
    @Environment(\.dismiss) private var dismiss

    /// `nil` shows the chooser — exactly the client's convention.
    private enum PhraseMode {
        case type
        case create
    }

    @State private var mode: PhraseMode?
    @State private var phrase = ""
    @State private var revealed = false
    @State private var isWorking = false
    @State private var showImporter = false
    @State private var showExporter = false
    @State private var copied = false
    @State private var localError: String?

    private var wordCount: Int { SpacechatAuth.wordCount(phrase) }
    private var canSubmit: Bool { SpacechatAuth.isValid(phrase) && !isWorking }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if mode == nil {
                        chooser
                    } else {
                        editor
                    }

                    if let message = localError ?? authState.errorMessage {
                        Text(message)
                            .font(.system(size: 12))
                            .foregroundColor(.red.opacity(0.85))
                    }
                }
                .padding(20)
            }
            .background(Color(white: 0.97).ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if mode == nil {
                        Button("Cancel") { dismiss() }
                    } else {
                        Button("Back") { backToChooser() }
                    }
                }
            }
            // Attached at this level, not inside a branch: a modifier on a
            // view that disappears when `mode` changes never gets to run its
            // completion handler.
            .fileImporter(isPresented: $showImporter,
                          allowedContentTypes: [.plainText, .text],
                          allowsMultipleSelection: false) { result in
                importPhrase(result)
            }
            .fileExporter(isPresented: $showExporter,
                          document: PhraseDocument(text: phrase),
                          contentType: .plainText,
                          defaultFilename: exportFileName()) { _ in }
        }
    }

    private var title: String {
        switch mode {
        case .none: return "Spacechat Phrase"
        case .type: return "Enter Your Phrase"
        case .create: return "New Phrase"
        }
    }

    // MARK: - 1. Chooser

    private var chooser: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Use your recovery phrase")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                Text("The same phrase works in Spacechat — it's one account across both.")
                    .font(.system(size: 13))
                    .foregroundColor(.black.opacity(0.6))
            }

            choiceButton(title: "Upload Existing Phrase",
                         subtitle: "Pick a saved phrase file",
                         icon: "square.and.arrow.up") {
                showImporter = true
            }

            choiceButton(title: "Type Existing Phrase",
                         subtitle: "Enter your 12 to 18 words",
                         icon: "keyboard") {
                phrase = ""
                revealed = true
                localError = nil
                authState.errorMessage = nil
                mode = .type
            }

            Divider().padding(.vertical, 2)

            choiceButton(title: "Create New Phrase",
                         subtitle: "Generate 12 words and start fresh",
                         icon: "sparkles",
                         prominent: true) {
                phrase = SpacechatAuth.generatePhrase()
                revealed = true
                localError = nil
                authState.errorMessage = nil
                mode = .create
                HapticsManager.shared.impact(.light)
            }
        }
    }

    private func choiceButton(title: String, subtitle: String, icon: String,
                              prominent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 15, weight: .semibold, design: .rounded))
                    Text(subtitle).font(.system(size: 12)).opacity(0.65)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).opacity(0.4)
            }
            .foregroundColor(prominent ? .white : .black)
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(prominent ? Color.black : Color.white,
                        in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(PressableButtonStyle(scale: 0.98))
    }

    // MARK: - 2. Editor (.type and .create)

    private var editor: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(mode == .create
                 ? "These 12 words are your new account. Save them somewhere safe before continuing."
                 : "Enter the 12 to 18 words for your account.")
                .font(.system(size: 13))
                .foregroundColor(.black.opacity(0.6))

            phraseField

            if mode == .create {
                createActions

                Label("Nobody can recover this phrase for you, and anyone who has it can sign in as you. Spacechat will never ask you for it.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.orange)
            }

            continueButton

            Text("Your phrase is stored in this device's Keychain and never leaves it except to sign in to Spacechat.")
                .font(.system(size: 11))
                .foregroundColor(.black.opacity(0.4))
        }
    }

    private var createActions: some View {
        HStack(spacing: 10) {
            smallAction("Generate", icon: "arrow.triangle.2.circlepath") {
                phrase = SpacechatAuth.generatePhrase()
                revealed = true
                copied = false
                HapticsManager.shared.impact(.light)
            }
            smallAction(copied ? "Copied" : "Copy", icon: copied ? "checkmark" : "doc.on.doc") {
                UIPasteboard.general.string = phrase
                copied = true
                HapticsManager.shared.impact(.light)
            }
            smallAction("Save", icon: "square.and.arrow.down") {
                showExporter = true
            }
        }
    }

    private func smallAction(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
        }
        .foregroundColor(.black)
        .background(Color.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        .buttonStyle(.plain)
    }

    private var phraseField: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: Binding(
                    get: { phrase },
                    set: { phrase = SpacechatAuth.normalizeForEditing($0); copied = false }
                ))
                .font(.system(size: 15, design: .monospaced))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .scrollContentBackground(.hidden)
                .frame(height: 112)
                .padding(8)
                .opacity(revealed ? 1 : 0.02)

                if !revealed {
                    Text(phrase.isEmpty ? "Type or paste your phrase" : "Phrase hidden")
                        .font(.system(size: 14))
                        .foregroundColor(.black.opacity(0.35))
                        .padding(14)
                        .allowsHitTesting(false)
                }
            }
            .background(Color.white, in: RoundedRectangle(cornerRadius: 12))

            HStack {
                Button(revealed ? "Hide words" : "Show words") { revealed.toggle() }
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Text("\(wordCount)/18 words")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(SpacechatAuth.isValid(phrase) ? .green : .black.opacity(0.4))
            }
        }
    }

    private var continueButton: some View {
        Button(action: submit) {
            Group {
                if isWorking {
                    ProgressView().tint(.white)
                } else {
                    Text(mode == .create ? "Create & Continue" : "Continue")
                }
            }
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .background(canSubmit ? Color.black : Color.black.opacity(0.25),
                    in: RoundedRectangle(cornerRadius: 14))
        .buttonStyle(PressableButtonStyle())
        .disabled(!canSubmit)
    }

    // MARK: - Actions

    private func backToChooser() {
        mode = nil
        phrase = ""
        revealed = false
        copied = false
        localError = nil
        authState.errorMessage = nil
    }

    /// Every export used to share one fixed name in the Spacechat client,
    /// which made a Files folder full of indistinguishable phrase files after
    /// a couple of accounts. A timestamp keeps them apart.
    private func exportFileName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return "spacechat-recovery-phrase-\(formatter.string(from: Date()))"
    }

    private func importPhrase(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            // A file picked outside the app's container is security scoped:
            // reading it without this returns nothing, with no error.
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
                localError = "Couldn't read that file."
                return
            }
            let candidate = SpacechatAuth.normalize(contents)
            guard SpacechatAuth.isValid(candidate) else {
                localError = "That file doesn't contain a 12 to 18 word phrase."
                return
            }
            // Upload lands in the same editor as Type, exactly like the
            // client — so an uploaded phrase can still be checked or fixed
            // before it's submitted.
            phrase = candidate
            revealed = false
            localError = nil
            mode = .type
        case .failure:
            localError = "Couldn't open that file."
        }
    }

    private func submit() {
        guard canSubmit else { return }
        isWorking = true
        localError = nil
        Task {
            let ok = await authState.signInWithSpacechat(phrase: phrase)
            isWorking = false
            if ok {
                HapticsManager.shared.success()
                onSignedIn()
                dismiss()
            }
        }
    }
}

/// Plain-text wrapper so a freshly created phrase can be written straight to
/// Files via `fileExporter`.
private struct PhraseDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }

    var text: String

    init(text: String) { self.text = text }

    init(configuration: ReadConfiguration) throws {
        let data = configuration.file.regularFileContents ?? Data()
        text = String(data: data, encoding: .utf8) ?? ""
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

import SwiftUI
import UniformTypeIdentifiers

/// Signing in with a Spacechat recovery phrase — the second route offered
/// under Sign in with Apple (§ new).
///
/// Three ways in, matching the Spacechat app: type an existing phrase,
/// generate a brand-new one, or upload a phrase file saved earlier. The
/// server creates the account when it doesn't recognize the phrase, so
/// "create" and "sign in" are the same call — there is no separate sign-up.
struct SpacechatPhraseView: View {
    @ObservedObject var authState: AuthState
    var onSignedIn: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var phrase = ""
    @State private var revealed = false
    @State private var isWorking = false
    @State private var showImporter = false
    @State private var justGenerated = false
    @State private var localError: String?

    private var wordCount: Int { SpacechatAuth.wordCount(phrase) }
    private var canSubmit: Bool { SpacechatAuth.isValid(phrase) && !isWorking }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header

                    phraseField

                    HStack(spacing: 10) {
                        Button {
                            phrase = SpacechatAuth.generatePhrase()
                            revealed = true
                            justGenerated = true
                            localError = nil
                            HapticsManager.shared.impact(.light)
                        } label: {
                            Label("Create new phrase", systemImage: "sparkles")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .foregroundColor(.black)
                        .background(Color.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))

                        Button { showImporter = true } label: {
                            Label("Upload", systemImage: "arrow.up.doc.fill")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .foregroundColor(.black)
                        .background(Color.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)

                    if justGenerated {
                        Label(
                            "Write these words down before continuing. This phrase IS your account — nobody can recover it for you, and anyone who has it can sign in as you.",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.system(size: 12))
                        .foregroundColor(.orange)
                    }

                    if let message = localError ?? authState.errorMessage {
                        Text(message)
                            .font(.system(size: 12))
                            .foregroundColor(.red.opacity(0.85))
                    }

                    Button(action: submit) {
                        Group {
                            if isWorking {
                                ProgressView().tint(.white)
                            } else {
                                Text("Continue")
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

                    Text("Your phrase is stored in this device's Keychain and never leaves it except to sign in to Spacechat.")
                        .font(.system(size: 11))
                        .foregroundColor(.black.opacity(0.4))
                }
                .padding(20)
            }
            .background(Color(white: 0.97).ignoresSafeArea())
            .navigationTitle("Spacechat Phrase")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .fileImporter(isPresented: $showImporter,
                          allowedContentTypes: [.plainText, .text],
                          allowsMultipleSelection: false) { result in
                importPhrase(result)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Use your recovery phrase")
                .font(.system(size: 19, weight: .bold, design: .rounded))
            Text("12 to 18 words. The same phrase works in Spacechat — signing in here uses the same account.")
                .font(.system(size: 13))
                .foregroundColor(.black.opacity(0.6))
        }
    }

    private var phraseField: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                // A phrase is long; a multi-line editor beats a single-line
                // field that scrolls its own start out of view.
                TextEditor(text: Binding(
                    get: { phrase },
                    set: { phrase = SpacechatAuth.normalizeForEditing($0) }
                ))
                .font(.system(size: 15, design: .monospaced))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .scrollContentBackground(.hidden)
                .frame(height: 110)
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

    private func importPhrase(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            // A file picked outside the app's own container is security
            // scoped: reading it without this returns nothing, with no error.
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
            phrase = candidate
            revealed = false
            justGenerated = false
            localError = nil
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

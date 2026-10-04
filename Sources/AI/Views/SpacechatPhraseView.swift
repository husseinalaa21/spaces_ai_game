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
    /// Create mode starts empty with Generate / Type buttons inside the field; typing instead hides them.
    @State private var manualEntry = false
    @State private var generatedPulse = false
    @FocusState private var phraseFocused: Bool

    private var wordCount: Int { SpacechatAuth.wordCount(phrase) }
    private var canSubmit: Bool { SpacechatAuth.isValid(phrase) && !isWorking }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Sign In | Log In")
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 8)
                        .accessibilityAddTraits(.isHeader)

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
            .scrollDismissesKeyboard(.interactively)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.97).ignoresSafeArea())
        .preferredColorScheme(.light)
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

    /// Full-width header: the grey bar runs edge to edge (and under the status
    /// bar), with the back / cancel button on the left and the logo and name centred.
    private var header: some View {
        ZStack {
            HStack(spacing: 8) {
                GameLogoMark(size: 30, animated: false)
                Text("Space Dots and AI")
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .tracking(0.6)
            }
            HStack {
                Button(mode == nil ? "Cancel" : "Back") {
                    if mode == nil { dismiss() } else { backToChooser() }
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.black.opacity(0.75))
                Spacer()
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(Color(white: 0.93).ignoresSafeArea(edges: .top))
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
                manualEntry = true
                localError = nil
                authState.errorMessage = nil
                mode = .type
            }

            Divider().padding(.vertical, 2)

            choiceButton(title: "Create New Phrase",
                         subtitle: "Generate 12 words and start fresh",
                         icon: "sparkles",
                         prominent: true) {
                phrase = ""
                revealed = true
                manualEntry = false
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
                 ? "Generate 12 words for your new account and save them somewhere safe before continuing."
                 : "Enter the 12 to 18 words for your account.")
                .font(.system(size: 13))
                .foregroundColor(.black.opacity(0.6))

            phraseField

            if mode == .create && !phrase.isEmpty {
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

    /// The words as numbered tiles, the way Spacechat's login shows a phrase once the field loses focus.
    private var tokens: [(index: Int, word: String, number: Int)] {
        let words = SpacechatAuth.normalize(phrase).split(separator: " ").map(String.init)
        let list = SpacechatWords.all
        return words.enumerated().map { i, word in (i, word, (list.firstIndex(of: word) ?? i) + 1) }
    }

    private var showsGenerate: Bool { mode == .create && phrase.isEmpty && !manualEntry }
    private var showsTiles: Bool { !phraseFocused && !tokens.isEmpty }

    private func generate() {
        phrase = SpacechatAuth.generatePhrase()
        revealed = true
        copied = false
        localError = nil
        HapticsManager.shared.impact(.light)
    }

    private var phraseField: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsTiles {
                HStack {
                    Spacer()
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) { revealed.toggle() }
                    } label: {
                        Label(revealed ? "Hide words" : "Click to view", systemImage: revealed ? "eye.slash.fill" : "eye.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.black.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                }
            }

            ZStack(alignment: .topLeading) {
                TextField("Enter your 12 to 18 word phrase", text: Binding(
                    get: { phrase },
                    set: { phrase = SpacechatAuth.normalizeForEditing($0); copied = false; localError = nil }
                ), axis: .vertical)
                .focused($phraseFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(size: 15, weight: .semibold))
                .tint(.black)
                .lineLimit(4...6)
                .padding(18)
                .frame(maxWidth: .infinity, minHeight: 188, maxHeight: 188, alignment: .topLeading)
                .opacity(showsTiles ? 0 : 1)
                .onAppear {
                    // Open ready to type or paste, without a second tap.
                    if mode == .type { DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { phraseFocused = true } }
                }
                .onChange(of: phraseFocused) { focused in if focused { revealed = false } }
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") { phraseFocused = false }.font(.system(size: 15, weight: .bold))
                    }
                }

                if showsTiles {
                    ScrollView(showsIndicators: false) {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 9)], alignment: .leading, spacing: 9) {
                            ForEach(tokens, id: \.index) { token in
                                HStack(spacing: 7) {
                                    Text("\(token.number).").font(.system(size: 12, weight: .semibold)).foregroundColor(.black.opacity(0.45))
                                    Text(revealed ? token.word : "\(token.word.first.map(String.init) ?? "")***")
                                        .font(.system(size: 14, weight: .semibold)).lineLimit(1)
                                }
                                .padding(.horizontal, 10)
                                .frame(minHeight: 34, alignment: .leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.black.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.black.opacity(0.75), lineWidth: 1))
                            }
                        }
                        .padding(18)
                    }
                    .frame(maxWidth: .infinity, minHeight: 188, maxHeight: 188, alignment: .topLeading)
                    .contentShape(Rectangle())
                    .simultaneousGesture(TapGesture().onEnded { phraseFocused = true })
                }
            }
            .frame(maxWidth: .infinity, minHeight: 188, maxHeight: 188, alignment: .topLeading)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(phraseFocused ? Color.black : Color.black.opacity(0.1), lineWidth: phraseFocused ? 2 : 1))
            .overlay {
                if showsGenerate { generateOverlay.transition(.opacity) }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .animation(.easeOut(duration: 0.18), value: showsGenerate)

            HStack {
                Spacer()
                Text("\(wordCount)/18 words")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(SpacechatAuth.isValid(phrase) ? .green : .black.opacity(0.4))
            }
        }
    }

    /// Inside the empty field of a new account: make a phrase, or type one you already have.
    private var generateOverlay: some View {
        VStack(spacing: 14) {
            Button(action: generate) {
                VStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 24, weight: .bold))
                        .scaleEffect(generatedPulse ? 1.14 : 1)
                        .opacity(generatedPulse ? 1 : 0.82)
                    Text("Generate").font(.system(size: 16, weight: .heavy, design: .rounded))
                }
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.black.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
            }
            .buttonStyle(PressableButtonStyle(scale: 0.98))
            .accessibilityHint("Creates a new recovery phrase.")

            Button {
                manualEntry = true
                phraseFocused = true
            } label: {
                Text("Type existing phrase")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.black.opacity(0.55))
                    .underline()
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { generatedPulse = true }
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
        manualEntry = false
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

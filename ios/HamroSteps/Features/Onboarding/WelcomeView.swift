import AuthenticationServices
import SwiftUI

/// First screen: what the app is, and Sign in with Apple. Only the first
/// name is requested from Apple; nothing else.
struct WelcomeView: View {
    @Environment(SessionStore.self) private var session
    @ScaledMetric(relativeTo: .largeTitle) private var markBase: CGFloat = 96
    @State private var isSigningIn = false
    @State private var message: String?

    var body: some View {
        ScrollView {
            VStack(spacing: Bento.gap) {
                hero
                VStack(alignment: .leading, spacing: 18) {
                    point(.family, "One shared step goal for the whole family.")
                    point(.health, "Your steps come from Apple Health. Nothing to type in.")
                    point(.goal, "See how the family is doing today at a glance.")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Bento.padding)
                .bentoSurface()
            }
            .padding(.horizontal, Bento.margin)
            .padding(.top, 16)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                if let message { Notice(text: message) }
                if isSigningIn {
                    OrbLoader(activity: .signingIn)
                } else {
                    SignInWithAppleButton(.continue) { request in
                        request.requestedScopes = [.fullName]
                    } onCompletion: { result in
                        handle(result)
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 56)
                    .clipShape(.capsule)
                    Link("Privacy policy", destination: URL(string: "https://subiixu.github.io/hamro-steps/privacy/")!)
                        .font(.subheadline)
                        .foregroundStyle(.secondaryText)
                    #if DEBUG
                    // The sample token only works against the mock services; the real
                    // `/auth/apple` rejects it, so the button shows on mock launches only.
                    if AppLaunch.isMockLaunch {
                        Button("Use the sample account (debug)") {
                            signIn(token: "debug-token", code: "debug-code", name: nil)
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondaryText)
                    }
                    #endif
                }
            }
            .padding(.horizontal, Bento.margin)
            .padding(.vertical, 16)
            .background(.canvas)
        }
        .background(.canvas)
    }

    /// The large hero tile: the app mark on a soft accent wash, the name and
    /// the one-line promise.
    private var hero: some View {
        VStack(spacing: 20) {
            Icon.home
                .size(markIcon)
                .foregroundStyle(.white)
                .frame(width: markSide, height: markSide)
                .background(.accent, in: .rect(cornerRadius: markSide * 0.28, style: .continuous))
                .accessibilityHidden(true)
            VStack(spacing: 10) {
                Text("Hamro Steps")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                Text("Walk together as a family, wherever you live.")
                    .font(.title3)
                    .foregroundStyle(.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Bento.padding)
        .padding(.vertical, 44)
        .bentoSurface(Color.accent.opacity(0.10))
        .background(.surface, in: .rect(cornerRadius: Bento.radius, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var markSide: CGFloat { min(markBase, 140) }
    private var markIcon: CGFloat { markSide * 0.5 }

    private func point(_ icon: Icon, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            icon.size(26).foregroundStyle(.accent)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 6 }
            Text(text).font(.body)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func handle(_ result: Result<ASAuthorization, any Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let token = String(data: tokenData, encoding: .utf8),
                  let codeData = credential.authorizationCode,
                  let code = String(data: codeData, encoding: .utf8)
            else {
                message = String(localized: "Apple didn't finish signing you in. Please try again.")
                return
            }
            signIn(token: token, code: code, name: credential.fullName)
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code == .canceled { return }
            message = String(localized: "Apple didn't finish signing you in. Please try again.")
        }
    }

    private func signIn(token: String, code: String, name: PersonNameComponents?) {
        message = nil
        isSigningIn = true
        Task {
            do {
                try await session.signIn(identityToken: token, authorizationCode: code, fullName: name)
            } catch let error as FamilyServiceError {
                message = error.message
            } catch {
                message = FamilyServiceError.unavailable("").message
            }
            isSigningIn = false
        }
    }
}

/// Apple sent no name: ask for a first name. This is the only typing a
/// joining parent does.
struct AskNameView: View {
    @Environment(SessionStore.self) private var session
    @State private var name = ""
    @State private var isSaving = false
    @State private var message: String?
    @FocusState private var focused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Bento.gap) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("What should your family call you?")
                        .font(.largeTitle.bold())
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Just your first name, or what they call you at home.")
                        .font(.body)
                        .foregroundStyle(.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 4)
                .padding(.top, 32)
                .padding(.bottom, 8)
                TextField("First name", text: $name)
                    .font(.title2)
                    .textContentType(.givenName)
                    .submitLabel(.done)
                    .focused($focused)
                    .fieldTile()
                    .onSubmit(save)
                if let message { Notice(text: message) }
            }
            .padding(.horizontal, Bento.margin)
        }
        .safeAreaInset(edge: .bottom) {
            Group {
                if isSaving {
                    OrbLoader(activity: .saving)
                } else {
                    PrimaryButton(title: "Continue", isEnabled: FamilyRules.isValidName(name), action: save)
                }
            }
            .padding(.horizontal, Bento.margin)
            .padding(.vertical, 16)
            .background(.canvas)
        }
        .background(.canvas)
        .onAppear { focused = true }
    }

    private func save() {
        guard FamilyRules.isValidName(name), !isSaving else { return }
        isSaving = true
        message = nil
        Task {
            do {
                try await session.saveName(name)
            } catch let error as FamilyServiceError {
                message = error.message
            } catch {
                message = FamilyServiceError.unavailable("").message
            }
            isSaving = false
        }
    }
}

#Preview("Welcome") {
    WelcomeView()
        .environment(SessionStore(auth: MockAuthService.preview, service: MockFamilyService.preview))
}

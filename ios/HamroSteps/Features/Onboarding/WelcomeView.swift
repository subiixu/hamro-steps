import AuthenticationServices
import SwiftUI

/// First screen: what the app is, and Sign in with Apple. Only the first
/// name is requested from Apple; nothing else.
struct WelcomeView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.colorScheme) private var colorScheme
    @State private var isSigningIn = false
    @State private var message: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                Icon.home
                    .size(64)
                    .foregroundStyle(.accent)
                    .frame(width: 128, height: 128)
                    .background(Color.accent.opacity(0.14), in: .circle)
                    .padding(.top, 48)

                VStack(spacing: 12) {
                    Text("Hamro Steps")
                        .font(.largeTitle.bold())
                    Text("Walk together as a family, wherever you live.")
                        .font(.title3)
                        .foregroundStyle(.secondaryText)
                        .multilineTextAlignment(.center)
                }

                VStack(alignment: .leading, spacing: 16) {
                    point(.family, "One shared step goal for the whole family.")
                    point(.health, "Your steps come from Apple Health. Nothing to type in.")
                    point(.goal, "See how the family is doing today at a glance.")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(24)
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
                    .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                    .frame(height: 56)
                    .clipShape(.capsule)
                    #if DEBUG
                    Button("Use the sample account (debug)") {
                        signIn(token: "debug-token", code: "debug-code", name: nil)
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondaryText)
                    #endif
                }
            }
            .padding(24)
            .background(.canvas)
        }
        .background(.canvas)
    }

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
            VStack(alignment: .leading, spacing: 20) {
                Text("What should your family call you?")
                    .font(.largeTitle.bold())
                    .padding(.top, 48)
                Text("Just your first name, or what they call you at home.")
                    .font(.body)
                    .foregroundStyle(.secondaryText)
                TextField("First name", text: $name)
                    .font(.title2)
                    .textContentType(.givenName)
                    .submitLabel(.done)
                    .focused($focused)
                    .padding(16)
                    .background(.surface, in: .rect(cornerRadius: 16))
                    .onSubmit(save)
                if let message { Notice(text: message) }
            }
            .padding(24)
        }
        .safeAreaInset(edge: .bottom) {
            Group {
                if isSaving {
                    OrbLoader(activity: .saving)
                } else {
                    PrimaryButton(title: "Continue", isEnabled: FamilyRules.isValidName(name), action: save)
                }
            }
            .padding(24)
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

import Foundation
import SwiftUI

@MainActor
final class AuthViewModel: ObservableObject {
    enum Mode: String, CaseIterable, Identifiable {
        case signIn
        case signUp

        var id: String { rawValue }

        var title: String {
            switch self {
            case .signIn:
                return "ログイン"
            case .signUp:
                return "新規登録"
            }
        }

        var actionTitle: String {
            switch self {
            case .signIn:
                return "ログイン"
            case .signUp:
                return "登録する"
            }
        }
    }

    @Published var mode: Mode = .signIn
    @Published var email: String = ""
    @Published var password: String = ""
    @Published var fullName: String = ""
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var currentUser: UserProfile?
    @Published private(set) var session: AuthSession?

    private let authService: AuthServicing
    private let sessionStore: AuthSessionStore

    var isAuthenticated: Bool {
        guard let session else { return false }
        return !session.isExpired
    }

    init(authService: AuthServicing = AuthService(), sessionStore: AuthSessionStore = AuthSessionStore()) {
        self.authService = authService
        self.sessionStore = sessionStore

        Task {
            await restoreSession()
        }
    }

    func submit() {
        errorMessage = nil

        guard validateInputs() else {
            errorMessage = "入力内容を確認してください。"
            return
        }

        isLoading = true

        Task {
            do {
                let response: AuthResponse
                switch mode {
                case .signIn:
                    response = try await authService.signIn(email: normalizedEmail, password: password)
                case .signUp:
                    response = try await authService.signUp(email: normalizedEmail, password: password, fullName: fullName)
                }

                let session = AuthSession(token: response.accessToken, expiryDate: response.expiryDate, user: response.user)
                try await sessionStore.save(session)
                await MainActor.run {
                    self.session = session
                    self.currentUser = response.user
                    self.password = ""
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                }
            }

            await MainActor.run {
                self.isLoading = false
            }
        }
    }

    func signOut() {
        Task {
            await sessionStore.clear()
            await MainActor.run {
                self.session = nil
                self.currentUser = nil
                self.email = ""
                self.password = ""
                self.fullName = ""
                self.mode = .signIn
            }
        }
    }

    func switchMode(_ mode: Mode) {
        guard self.mode != mode else { return }
        errorMessage = nil
        password = ""
        if mode == .signIn {
            fullName = ""
        }
        self.mode = mode
    }

    private var normalizedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func validateInputs() -> Bool {
        guard normalizedEmail.contains("@"), normalizedEmail.contains(".") else { return false }
        guard password.count >= 8 else { return false }
        if mode == .signUp {
            return !fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return true
    }

    private func restoreSession() async {
        if let existingSession = await sessionStore.load(), !existingSession.isExpired {
            await MainActor.run {
                self.session = existingSession
                self.currentUser = existingSession.user
                self.email = existingSession.user.email
            }
        } else {
            await sessionStore.clear()
        }
    }
}

import Foundation

struct AuthResponse: Decodable {
    let accessToken: String
    let user: UserProfile
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case user
        case expiresIn = "expires_in"
    }

    var expiryDate: Date {
        Date().addingTimeInterval(Double(expiresIn))
    }
}

struct AuthErrorResponse: Decodable {
    let error: String?
    let message: String?
}

protocol AuthServicing {
    func signUp(email: String, password: String, fullName: String) async throws -> AuthResponse
    func signIn(email: String, password: String) async throws -> AuthResponse
}

enum AuthServiceError: LocalizedError {
    case invalidURL
    case httpError(statusCode: Int, message: String?)
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "無効なURLです。"
        case .httpError(_, let message):
            return message ?? "サーバーエラーが発生しました。"
        case .decodingFailed:
            return "サーバーレスポンスの解析に失敗しました。"
        }
    }
}

final class AuthService: AuthServicing {
    private let baseURL: URL
    private let urlSession: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(baseURL: URL = AppConfiguration.apiBaseURL,
         urlSession: URLSession = .shared,
         decoder: JSONDecoder = JSONDecoder(),
         encoder: JSONEncoder = JSONEncoder()) {
        self.baseURL = baseURL
        self.urlSession = urlSession
        self.decoder = decoder
        self.encoder = encoder
        self.decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.encoder.keyEncodingStrategy = .useDefaultKeys
    }

    func signUp(email: String, password: String, fullName: String) async throws -> AuthResponse {
        let payload = SignUpPayload(email: email, password: password, fullName: fullName)
        let request = try makeRequest(path: "/auth/signup", method: "POST", body: payload)
        return try await perform(request: request, expectingStatus: 201)
    }

    func signIn(email: String, password: String) async throws -> AuthResponse {
        let payload = SignInPayload(email: email, password: password)
        let request = try makeRequest(path: "/auth/signin", method: "POST", body: payload)
        return try await perform(request: request, expectingStatus: 200)
    }

    private func makeRequest<T: Encodable>(path: String, method: String, body: T) throws -> URLRequest {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw AuthServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        return request
    }

    private func perform(request: URLRequest, expectingStatus statusCode: Int) async throws -> AuthResponse {
        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthServiceError.httpError(statusCode: -1, message: "無効なレスポンスです。")
        }

        guard httpResponse.statusCode == statusCode else {
            let message = try? decoder.decode(AuthErrorResponse.self, from: data).message
            throw AuthServiceError.httpError(statusCode: httpResponse.statusCode, message: message)
        }

        guard let authResponse = try? decoder.decode(AuthResponse.self, from: data) else {
            throw AuthServiceError.decodingFailed
        }

        return authResponse
    }
}

private struct SignUpPayload: Encodable {
    let email: String
    let password: String
    let fullName: String

    enum CodingKeys: String, CodingKey {
        case email
        case password
        case fullName = "full_name"
    }
}

private struct SignInPayload: Encodable {
    let email: String
    let password: String
}

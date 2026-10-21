import Foundation
import AuthenticationServices
import CryptoKit
import UIKit

/// Konfiguration aus Info.plist (Werte kommen aus Config/Secrets.xcconfig – nicht einchecken!).
enum GarminConfig {
    static var clientID: String { Bundle.main.object(forInfoDictionaryKey: "GARMIN_CLIENT_ID") as? String ?? "" }
    static var backendURL: URL? {
        guard let s = Bundle.main.object(forInfoDictionaryKey: "TRICOACH_BACKEND_URL") as? String, !s.isEmpty else { return nil }
        return URL(string: s)
    }
    static let callbackScheme = "tricoach"
    static let redirectURI = "tricoach://garmin-callback"
    /// Garmin OAuth2-PKCE Consent-Seite
    static let authorizeURL = URL(string: "https://connect.garmin.com/oauth2Confirm")!

    static var isConfigured: Bool { !clientID.isEmpty && backendURL != nil }
    static let sessionTokenKey = "garmin.backendSession"
    static var isConnected: Bool { KeychainStore.get(sessionTokenKey) != nil }
}

enum PKCE {
    static func makeVerifier() -> String {
        let chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return String((0..<64).map { _ in chars.randomElement()! })
    }

    static func challenge(for verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// OAuth 2.0 + PKCE gegen Garmin Connect.
///
/// Ablauf:
/// 1. App öffnet die Garmin-Consent-Seite (ASWebAuthenticationSession) mit code_challenge.
/// 2. Garmin leitet auf tricoach://garmin-callback?code=…&state=… zurück.
/// 3. App schickt code + code_verifier an das eigene Backend.
/// 4. Backend tauscht den Code (mit client_secret!) gegen Access/Refresh-Token,
///    speichert sie serverseitig und gibt der App ein eigenes Session-Token zurück.
/// Das client_secret gehört nie in die App.
@MainActor
final class GarminAuthService: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = GarminAuthService()

    private var session: ASWebAuthenticationSession?

    enum AuthError: LocalizedError {
        case notConfigured, cancelled, stateMismatch, missingCode
        var errorDescription: String? {
            switch self {
            case .notConfigured: return "Garmin Client-ID oder Backend-URL fehlen (Config/Secrets.xcconfig)."
            case .cancelled: return "Anmeldung abgebrochen."
            case .stateMismatch: return "Sicherheitsprüfung (state) fehlgeschlagen."
            case .missingCode: return "Garmin hat keinen Autorisierungscode geliefert."
            }
        }
    }

    func connect() async throws {
        guard GarminConfig.isConfigured, let backend = GarminConfig.backendURL else { throw AuthError.notConfigured }
        let verifier = PKCE.makeVerifier()
        let state = UUID().uuidString

        var components = URLComponents(url: GarminConfig.authorizeURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: GarminConfig.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "code_challenge", value: PKCE.challenge(for: verifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "redirect_uri", value: GarminConfig.redirectURI),
            URLQueryItem(name: "state", value: state)
        ]

        let callback: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: components.url!, callbackURLScheme: GarminConfig.callbackScheme) { url, error in
                if let url { continuation.resume(returning: url) }
                else { continuation.resume(throwing: error ?? AuthError.cancelled) }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            session.start()
        }
        session = nil

        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard items.first(where: { $0.name == "state" })?.value == state else { throw AuthError.stateMismatch }
        guard let code = items.first(where: { $0.name == "code" })?.value else { throw AuthError.missingCode }

        // Code-Tausch über das eigene Backend
        var request = URLRequest(url: backend.appendingPathComponent("v1/garmin/oauth/exchange"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode([
            "code": code, "codeVerifier": verifier, "redirectUri": GarminConfig.redirectURI
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw DataSourceError.invalidResponse((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        struct ExchangeResponse: Decodable { let sessionToken: String }
        let token = try JSONDecoder().decode(ExchangeResponse.self, from: data).sessionToken
        try KeychainStore.set(token, for: GarminConfig.sessionTokenKey)
    }

    func disconnect() async {
        if let backend = GarminConfig.backendURL, let token = KeychainStore.get(GarminConfig.sessionTokenKey) {
            var request = URLRequest(url: backend.appendingPathComponent("v1/garmin/registration"))
            request.httpMethod = "DELETE"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            _ = try? await URLSession.shared.data(for: request)
        }
        KeychainStore.delete(GarminConfig.sessionTokenKey)
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first(where: \.isKeyWindow) ?? ASPresentationAnchor()
        }
    }
}

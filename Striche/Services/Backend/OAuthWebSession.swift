import Foundation
import AuthenticationServices

// MARK: - OAuth2 browser hand-off
//
// Opens the provider's consent screen in a secure `ASWebAuthenticationSession`
// and resolves once the flow redirects back to our custom URL scheme
// (`striche://oauth?code=...`). The web client redirects to our website bounce
// page (https), which immediately forwards to the app scheme so the session can
// intercept it – Google "Web" clients don't allow custom-scheme redirects.

enum OAuthWebError: LocalizedError {
    case cannotStart
    case cancelled
    case noCode

    var errorDescription: String? {
        switch self {
        case .cannotStart: return "Browser-Anmeldung konnte nicht gestartet werden."
        case .cancelled:   return "Anmeldung abgebrochen."
        case .noCode:      return "Kein Anmelde-Code erhalten."
        }
    }
}

@MainActor
final class OAuthWebSession: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    /// Present `url`, wait for a redirect to `callbackScheme://…`, return that URL.
    func authenticate(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url, callbackURLScheme: callbackScheme
            ) { callbackURL, error in
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else if let error,
                          (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
                    continuation.resume(throwing: OAuthWebError.cancelled)
                } else {
                    continuation.resume(throwing: error ?? OAuthWebError.cancelled)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            if !session.start() {
                continuation.resume(throwing: OAuthWebError.cannotStart)
            }
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}

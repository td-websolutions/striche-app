import Foundation
import Security

// MARK: - Backend auth session
//
// Hält den Login-Zustand gegen das PocketBase-Backend. Läuft PARALLEL zum lokalen
// AppStore (JSON) – die App funktioniert weiter offline/lokal, dieses Objekt ist
// die Brücke fürs spätere Multi-Device-Sync. Der Token wird im Keychain gehalten,
// damit er Neustarts überlebt und nicht im JSON/UserDefaults landet.

@MainActor
final class BackendSession: ObservableObject {
    /// Eingeloggter Backend-User (PocketBase-Record), sonst nil.
    @Published private(set) var user: UserRecord?
    /// Läuft gerade ein Auth-Request?
    @Published private(set) var isWorking = false
    /// Letzter Fehler (für UI-Anzeige), wird bei neuem Versuch geleert.
    @Published private(set) var lastError: String?

    var isLoggedIn: Bool { user != nil && token != nil }
    var userID: String? { user?.id }

    private let client: PocketBaseClient
    private let keychainAccount = "de.verein.striche.backendToken"

    /// Aktueller Auth-Token (Keychain-backed). nil = nicht angemeldet.
    private(set) var token: String? {
        didSet {
            guard token != oldValue else { return }
            if let token {
                Keychain.set(token, account: keychainAccount)
            } else {
                Keychain.delete(account: keychainAccount)
            }
        }
    }

    init(client: PocketBaseClient = PocketBaseClient()) {
        self.client = client
        self.token = Keychain.get(account: keychainAccount)
    }

    // MARK: - Lifecycle

    /// Beim App-Start: vorhandenen Token validieren/erneuern. Schlägt es fehl
    /// (abgelaufen/ungültig), wird ausgeloggt – ohne den lokalen Store anzufassen.
    func restore() async {
        guard let token else { return }
        do {
            let auth = try await client.authRefresh(token: token, returning: UserRecord.self)
            self.token = auth.token
            self.user = auth.record
        } catch {
            self.token = nil
            self.user = nil
        }
    }

    // MARK: - Auth

    func register(email: String, password: String, name: String, emoji: String) async -> Bool {
        await run {
            let create = UserCreate(
                email: email,
                password: password,
                passwordConfirm: password,
                name: name,
                emoji: emoji
            )
            _ = try await self.client.createUser(body: create, returning: UserRecord.self)
            // Direkt einloggen, damit wir Token + Record haben.
            let auth = try await self.client.authWithPassword(
                identity: email, password: password, returning: UserRecord.self)
            self.token = auth.token
            self.user = auth.record
        }
    }

    func login(email: String, password: String) async -> Bool {
        await run {
            let auth = try await self.client.authWithPassword(
                identity: email, password: password, returning: UserRecord.self)
            self.token = auth.token
            self.user = auth.record
        }
    }

    func logout() {
        token = nil
        user = nil
        lastError = nil
    }

    // MARK: - Helper

    /// Führt einen Auth-Block aus, mappt Fehler in `lastError` und liefert Erfolg.
    private func run(_ work: @escaping () async throws -> Void) async -> Bool {
        isWorking = true
        lastError = nil
        defer { isWorking = false }
        do {
            try await work()
            return true
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }
}

// MARK: - Minimal Keychain wrapper (nur für den Auth-Token)

private enum Keychain {
    static func set(_ value: String, account: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            SecItemAdd(query.merging(attributes) { $1 } as CFDictionary, nil)
        }
    }

    static func get(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

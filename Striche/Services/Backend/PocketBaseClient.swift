import Foundation

// MARK: - Backend configuration

/// Central place to point the app at the Striche backend (PocketBase on Contabo).
/// `api.striche-app.de` bekommt automatisch HTTPS, sobald die DNS-Delegation live ist.
enum BackendConfig {
    /// Production API base URL.
    static let baseURL = URL(string: "https://api.striche-app.de")!

    /// Override at runtime (z. B. für lokales Testen über IP/sslip.io), sonst `baseURL`.
    static var overrideURL: URL?

    static var current: URL { overrideURL ?? baseURL }
}

// MARK: - Errors

enum PocketBaseError: LocalizedError {
    case invalidResponse
    case http(status: Int, message: String, data: PBErrorData?)
    case decoding(String)
    case notAuthenticated
    case transport(Error)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Ungültige Antwort vom Server."
        case let .http(status, message, _):
            return message.isEmpty ? "Serverfehler (\(status))." : message
        case let .decoding(detail):
            return "Antwort konnte nicht gelesen werden: \(detail)"
        case .notAuthenticated:
            return "Nicht angemeldet."
        case let .transport(error):
            return error.localizedDescription
        }
    }
}

/// Structured PocketBase error body: `{ "code", "message", "data": { field: { code, message } } }`.
struct PBErrorData: Decodable {
    let code: Int
    let message: String
    let data: [String: PBFieldError]?

    struct PBFieldError: Decodable {
        let code: String
        let message: String
    }
}

// MARK: - Generic record envelopes

/// Fields every PocketBase record carries.
protocol PBRecord: Codable, Identifiable {
    var id: String { get }
}

/// Paged list response: `{ page, perPage, totalItems, totalPages, items: [...] }`.
struct PBList<T: Decodable>: Decodable {
    let page: Int
    let perPage: Int
    let totalItems: Int
    let totalPages: Int
    let items: [T]
}

/// Auth response from `auth-with-password` / `auth-refresh`.
struct PBAuth<U: Decodable>: Decodable {
    let token: String
    let record: U
}

// MARK: - Client

/// Thin async wrapper around the PocketBase REST API. Stateless apart from the
/// base URL – the caller passes the auth token, so this stays easy to test.
struct PocketBaseClient {
    var baseURL: URL
    var session: URLSession

    init(baseURL: URL = BackendConfig.current, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    // PocketBase serialises dates as "2026-06-19 10:00:00.000Z".
    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSZ"
        return f
    }()

    static func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            if raw.isEmpty { return Date(timeIntervalSince1970: 0) }
            if let date = dateFormatter.date(from: raw) { return date }
            if let iso = ISO8601DateFormatter().date(from: raw) { return iso }
            return Date(timeIntervalSince1970: 0)
        }
        return d
    }

    static func makeEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer()
            try c.encode(dateFormatter.string(from: date))
        }
        return e
    }

    private func collectionURL(_ collection: String) -> URL {
        baseURL.appendingPathComponent("api/collections/\(collection)/records")
    }

    // MARK: Core request

    private func send<T: Decodable>(
        _ request: URLRequest,
        as type: T.Type
    ) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw PocketBaseError.transport(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw PocketBaseError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = try? Self.makeDecoder().decode(PBErrorData.self, from: data)
            throw PocketBaseError.http(status: http.statusCode,
                                       message: body?.message ?? "",
                                       data: body)
        }
        if T.self == EmptyResponse.self, let empty = EmptyResponse() as? T {
            return empty
        }
        do {
            return try Self.makeDecoder().decode(T.self, from: data)
        } catch {
            throw PocketBaseError.decoding(String(describing: error))
        }
    }

    private func request(
        _ method: String,
        url: URL,
        token: String?,
        body: Data? = nil
    ) -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = method
        if let body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let token {
            // PocketBase 0.23+ accepts the raw token in the Authorization header.
            req.setValue(token, forHTTPHeaderField: "Authorization")
        }
        return req
    }

    // MARK: Health

    /// Returns true if the API answers `{"code":200}` at /api/health.
    func health() async -> Bool {
        let url = baseURL.appendingPathComponent("api/health")
        let req = request("GET", url: url, token: nil)
        let result = try? await send(req, as: PBHealth.self)
        return result?.code == 200
    }

    // MARK: Auth

    /// Create a new user (member) account.
    func createUser<U: Decodable>(
        body: Encodable,
        returning: U.Type
    ) async throws -> U {
        let url = collectionURL("users")
        let payload = try Self.makeEncoder().encode(AnyEncodable(body))
        let req = request("POST", url: url, token: nil, body: payload)
        return try await send(req, as: U.self)
    }

    /// Email + password login. Returns `{ token, record }`.
    func authWithPassword<U: Decodable>(
        identity: String,
        password: String,
        returning: U.Type
    ) async throws -> PBAuth<U> {
        let url = baseURL.appendingPathComponent("api/collections/users/auth-with-password")
        let payload = try Self.makeEncoder().encode(["identity": identity, "password": password])
        let req = request("POST", url: url, token: nil, body: payload)
        return try await send(req, as: PBAuth<U>.self)
    }

    /// Refresh / validate the current token, returning a fresh one.
    func authRefresh<U: Decodable>(
        token: String,
        returning: U.Type
    ) async throws -> PBAuth<U> {
        let url = baseURL.appendingPathComponent("api/collections/users/auth-refresh")
        let req = request("POST", url: url, token: token)
        return try await send(req, as: PBAuth<U>.self)
    }

    /// Ask PocketBase to (re)send the e-mail verification message. Returns 204.
    func requestVerification(email: String) async throws {
        let url = baseURL.appendingPathComponent("api/collections/users/request-verification")
        let payload = try Self.makeEncoder().encode(["email": email])
        let req = request("POST", url: url, token: nil, body: payload)
        _ = try await send(req, as: EmptyResponse.self)
    }

    /// Ask PocketBase to send the password-reset e-mail. Returns 204.
    func requestPasswordReset(email: String) async throws {
        let url = baseURL.appendingPathComponent("api/collections/users/request-password-reset")
        let payload = try Self.makeEncoder().encode(["email": email])
        let req = request("POST", url: url, token: nil, body: payload)
        _ = try await send(req, as: EmptyResponse.self)
    }

    // MARK: Generic CRUD

    func list<T: Decodable>(
        _ collection: String,
        token: String?,
        filter: String? = nil,
        sort: String? = nil,
        expand: String? = nil,
        page: Int = 1,
        perPage: Int = 200
    ) async throws -> PBList<T> {
        var comps = URLComponents(url: collectionURL(collection), resolvingAgainstBaseURL: false)!
        var items = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "perPage", value: String(perPage)),
        ]
        if let filter { items.append(URLQueryItem(name: "filter", value: filter)) }
        if let sort { items.append(URLQueryItem(name: "sort", value: sort)) }
        if let expand { items.append(URLQueryItem(name: "expand", value: expand)) }
        comps.queryItems = items
        let req = request("GET", url: comps.url!, token: token)
        return try await send(req, as: PBList<T>.self)
    }

    func create<T: Decodable>(
        _ collection: String,
        body: Encodable,
        token: String?,
        returning: T.Type
    ) async throws -> T {
        let payload = try Self.makeEncoder().encode(AnyEncodable(body))
        let req = request("POST", url: collectionURL(collection), token: token, body: payload)
        return try await send(req, as: T.self)
    }

    func update<T: Decodable>(
        _ collection: String,
        id: String,
        body: Encodable,
        token: String?,
        returning: T.Type
    ) async throws -> T {
        let url = collectionURL(collection).appendingPathComponent(id)
        let payload = try Self.makeEncoder().encode(AnyEncodable(body))
        let req = request("PATCH", url: url, token: token, body: payload)
        return try await send(req, as: T.self)
    }

    func delete(
        _ collection: String,
        id: String,
        token: String?
    ) async throws {
        let url = collectionURL(collection).appendingPathComponent(id)
        let req = request("DELETE", url: url, token: token)
        _ = try await send(req, as: EmptyResponse.self)
    }

    // MARK: Custom endpoints (pb_hooks)

    /// Call a custom server route such as `api/striche/clubs` or `api/striche/join`.
    /// These run server-side with elevated access to create the membership the
    /// schema rules forbid clients from creating directly.
    func call<T: Decodable>(
        _ path: String,
        method: String = "POST",
        body: Encodable? = nil,
        token: String?,
        returning: T.Type
    ) async throws -> T {
        let url = baseURL.appendingPathComponent(path)
        let payload = try body.map { try Self.makeEncoder().encode(AnyEncodable($0)) }
        let req = request(method, url: url, token: token, body: payload)
        return try await send(req, as: T.self)
    }
}

// MARK: - Helpers

struct PBHealth: Decodable { let code: Int }

struct EmptyResponse: Decodable { init() {} }

/// Type-erased Encodable so generic bodies can be passed without protocol gymnastics.
struct AnyEncodable: Encodable {
    private let encodeFunc: (Encoder) throws -> Void
    init(_ wrapped: Encodable) { encodeFunc = wrapped.encode }
    func encode(to encoder: Encoder) throws { try encodeFunc(encoder) }
}

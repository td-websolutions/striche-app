import Foundation

// MARK: - PocketBase record DTOs
//
// Diese Structs spiegeln 1:1 die Collections im PocketBase-Schema
// (server/pocketbase/pb_migrations/1781870000_striche_schema.js).
// IDs sind PocketBase-Strings (15 Zeichen), Relationen sind die IDs der Zielrecords.
//
// Hinweis: ein paar lokale Drink-Felder (category, sound, symbol) sind im
// Backend-Schema (noch) nicht abgebildet. Beim Mapping werden sie mit sinnvollen
// Defaults gefüllt; bei Bedarf später per Migration ergänzen.

struct UserRecord: PBRecord {
    let id: String
    var email: String
    var name: String?
    var emoji: String?
    var verified: Bool?
    var created: Date?
    var updated: Date?
}

struct ClubRecord: PBRecord {
    let id: String
    var name: String
    var tagline: String?
    var invite_code: String?
    var open_invite: Bool?
    var latitude: Double?
    var longitude: Double?
    var geofence_radius: Double?
    var plan_id: String?
    var pending_plan_id: String?
    var getraenkewart_email: String?
    var created: Date?
    var updated: Date?
}

struct MembershipRecord: PBRecord {
    let id: String
    var user: String
    var club: String
    var role: String      // "admin" | "member"
    var invited: Bool?
    var created: Date?
    var updated: Date?
}

struct DrinkSizeDTO: Codable, Hashable {
    var label: String
    var priceModifier: Double
}

struct DrinkRecord: PBRecord {
    let id: String
    var club: String
    var name: String
    var emoji: String?
    var icon_symbol: String?
    var tint: String?
    var price: Double?
    var sizes: [DrinkSizeDTO]?
    var sort_order: Double?
    var created: Date?
    var updated: Date?
}

struct BookingRecord: PBRecord {
    let id: String
    var club: String
    var member: String
    var drink: String?
    var drink_name: String?
    var size_label: String?
    var price: Double?
    var paid: Bool?
    var date: Date?
    var created: Date?
    var updated: Date?
}

struct CreditTxRecord: PBRecord {
    let id: String
    var club: String
    var member: String
    var amount: Double?
    var kind: String      // "top_up" | "settlement"
    var note: String?
    var date: Date?
    var created: Date?
    var updated: Date?
}

struct WatchLinkRecord: PBRecord {
    let id: String
    var club: String
    var booker: String
    var watcher: String
    var status: String    // "pending" | "accepted" | "declined"
    var created: Date?
    var updated: Date?
}

// MARK: - Create / update payloads
//
// Beim Schreiben schicken wir nur die nötigen Felder (kein id/created/updated).

struct UserCreate: Encodable {
    var email: String
    var password: String
    var passwordConfirm: String
    var name: String
    var emoji: String
}

struct ClubWrite: Encodable {
    var name: String
    var tagline: String?
    var invite_code: String?
    var open_invite: Bool?
    var latitude: Double?
    var longitude: Double?
    var geofence_radius: Double?
    var plan_id: String?
    var pending_plan_id: String?
    var getraenkewart_email: String?
}

struct MembershipWrite: Encodable {
    var user: String
    var club: String
    var role: String
    var invited: Bool?
}

struct DrinkWrite: Encodable {
    var club: String
    var name: String
    var emoji: String?
    var icon_symbol: String?
    var tint: String?
    var price: Double?
    var sizes: [DrinkSizeDTO]?
    var sort_order: Double?
}

struct BookingWrite: Encodable {
    var club: String
    var member: String
    var drink: String?
    var drink_name: String?
    var size_label: String?
    var price: Double?
    var paid: Bool?
    var date: Date?
}

struct CreditTxWrite: Encodable {
    var club: String
    var member: String
    var amount: Double?
    var kind: String
    var note: String?
    var date: Date?
}

struct WatchLinkWrite: Encodable {
    var club: String
    var booker: String
    var watcher: String
    var status: String
}

// MARK: - Mapping zwischen Backend-DTOs und lokalen Models

extension CreditKind {
    var backendValue: String {
        switch self {
        case .topUp: return "top_up"
        case .settlement: return "settlement"
        }
    }
    init?(backend: String) {
        switch backend {
        case "top_up": self = .topUp
        case "settlement": self = .settlement
        default: return nil
        }
    }
}

extension WatchStatus {
    init(backend: String) {
        self = WatchStatus(rawValue: backend) ?? .pending
    }
}

extension DrinkRecord {
    /// Best-effort Mapping in das lokale Drink-Model. category/sound/symbol sind
    /// im Backend nicht hinterlegt und werden hier per Heuristik/Default gesetzt.
    func toLocalDrink() -> Drink {
        Drink(
            name: name,
            emoji: emoji ?? "🍺",
            symbol: "cup.and.saucer.fill",
            price: price ?? 0,
            category: .soft,
            tintHex: tint ?? "#2EC4F0",
            sizes: (sizes ?? []).map { DrinkSize(label: $0.label, priceModifier: $0.priceModifier) },
            sound: .generic,
            iconSymbol: icon_symbol
        )
    }
}

extension Drink {
    /// Local -> backend write payload for a given club.
    func toWrite(clubID: String, sortOrder: Int) -> DrinkWrite {
        DrinkWrite(
            club: clubID,
            name: name,
            emoji: emoji,
            icon_symbol: iconSymbol,
            tint: tintHex,
            price: price,
            sizes: sizes.map { DrinkSizeDTO(label: $0.label, priceModifier: $0.priceModifier) },
            sort_order: Double(sortOrder)
        )
    }
}

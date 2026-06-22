import Foundation
import SwiftUI

// MARK: - Drink

/// A selectable volume / variant of a drink (e.g. Weizen 0,3 / 0,5).
struct DrinkSize: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var label: String          // "0,3 l"
    var priceModifier: Double  // added to base price

    init(id: UUID = UUID(), label: String, priceModifier: Double = 0) {
        self.id = id
        self.label = label
        self.priceModifier = priceModifier
    }
}

struct Drink: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var emoji: String          // big tasty emoji used on the card
    var symbol: String         // SF Symbol fallback / accent
    var price: Double          // base price in EUR
    var category: DrinkCategory
    var tintHex: String        // accent color of the card
    var sizes: [DrinkSize]     // empty -> single price, no chooser
    var sound: DrinkSound      // which bundled sound to play
    var iconSymbol: String?    // optional SF Symbol shown instead of emoji (e.g. white-wine glass)
    var remoteID: String?      // PocketBase record id once synced (nil = local-only)

    init(id: UUID = UUID(),
         name: String,
         emoji: String,
         symbol: String = "cup.and.saucer.fill",
         price: Double,
         category: DrinkCategory,
         tintHex: String,
         sizes: [DrinkSize] = [],
         sound: DrinkSound = .generic,
         iconSymbol: String? = nil) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.symbol = symbol
        self.price = price
        self.category = category
        self.tintHex = tintHex
        self.sizes = sizes
        self.sound = sound
        self.iconSymbol = iconSymbol
    }

    var tint: Color { Color(hex: tintHex) }
}

enum DrinkCategory: String, Codable, CaseIterable, Identifiable {
    case beer = "Bier"
    case wine = "Wein & Sekt"
    case soft = "Alkoholfrei"
    case hot = "Heißgetränke"
    case snack = "Snacks"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .beer: return "mug.fill"
        case .wine: return "wineglass.fill"
        case .soft: return "waterbottle.fill"
        case .hot: return "cup.and.saucer.fill"
        case .snack: return "carrot.fill"
        }
    }
}

/// Maps to a bundled .mp3 (falls back to a synthesized tone if missing).
enum DrinkSound: String, Codable {
    case beer, sekt, coffee, grill, generic

    var fileName: String? {
        switch self {
        case .beer: return "bier"
        case .sekt: return "sekt"
        case .coffee: return "kaffee"
        case .grill: return "grill"
        case .generic: return nil
        }
    }
}

// MARK: - Member

struct Member: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var email: String
    var passwordHash: String?      // nil = invited but not registered yet
    var isAdmin: Bool
    var emoji: String              // avatar emoji
    var avatarData: Data?          // optional custom profile photo (overrides emoji)
    var joined: Date
    var remoteID: String?          // PocketBase user id once synced (nil = local-only / invite)

    init(id: UUID = UUID(),
         name: String,
         email: String,
         passwordHash: String? = nil,
         isAdmin: Bool = false,
         emoji: String = "🧑",
         avatarData: Data? = nil,
         joined: Date = .now) {
        self.id = id
        self.name = name
        self.email = email.lowercased()
        self.passwordHash = passwordHash
        self.isAdmin = isAdmin
        self.emoji = emoji
        self.avatarData = avatarData
        self.joined = joined
    }

    var avatarImage: UIImage? {
        guard let avatarData else { return nil }
        return UIImage(data: avatarData)
    }
}

// MARK: - Booking

struct Booking: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var memberID: UUID
    var drinkID: UUID
    var drinkName: String
    var sizeLabel: String?
    var price: Double
    var date: Date
    var paid: Bool
    var remoteID: String?      // PocketBase record id once synced (nil = local-only)

    init(id: UUID = UUID(),
         memberID: UUID,
         drinkID: UUID,
         drinkName: String,
         sizeLabel: String? = nil,
         price: Double,
         date: Date = .now,
         paid: Bool = false) {
        self.id = id
        self.memberID = memberID
        self.drinkID = drinkID
        self.drinkName = drinkName
        self.sizeLabel = sizeLabel
        self.price = price
        self.date = date
        self.paid = paid
    }
}

// MARK: - Credit (Guthaben) ledger

enum CreditKind: String, Codable {
    case topUp        // admin loaded credit (e.g. paid cash)
    case settlement   // admin marked the open tab as paid
}

/// A positive credit added to a member's account by an admin.
struct CreditTransaction: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var memberID: UUID
    var amount: Double      // always positive
    var kind: CreditKind
    var date: Date
    var note: String?
    var remoteID: String?   // PocketBase record id once synced (nil = local-only)

    init(id: UUID = UUID(), memberID: UUID, amount: Double,
         kind: CreditKind, date: Date = .now, note: String? = nil) {
        self.id = id
        self.memberID = memberID
        self.amount = amount
        self.kind = kind
        self.date = date
        self.note = note
    }
}

// MARK: - Watch link (per-member notification consent)

enum WatchStatus: String, Codable {
    case pending    // booker asked, watcher hasn't decided
    case accepted   // watcher agreed to be notified
    case declined   // watcher said no
}

/// "When `booker` books a drink on site, notify `watcher`."
/// Created by the booker, but only active once the watcher accepts.
struct WatchLink: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var bookerID: UUID
    var watcherID: UUID
    var status: WatchStatus
    var created: Date
    var remoteID: String?   // PocketBase record id once synced (nil = local-only)

    init(id: UUID = UUID(), bookerID: UUID, watcherID: UUID,
         status: WatchStatus = .pending, created: Date = .now) {
        self.id = id
        self.bookerID = bookerID
        self.watcherID = watcherID
        self.status = status
        self.created = created
    }
}

// MARK: - Club

struct Club: Identifiable, Codable {
    var id: UUID = UUID()
    var name: String
    var logoData: Data?
    var tagline: String
    var latitude: Double?
    var longitude: Double?
    var geofenceRadius: Double      // meters
    var inviteCode: String          // shared invite link token
    var openInvite: Bool            // anyone with the link may join automatically
    var planID: String              // active/licensed seat plan (billed by invoice)
    var pendingPlanID: String?      // requested upgrade awaiting invoice/confirmation
    var getraenkewartEmail: String? // empty-drink reports are sent here
    var remoteID: String?           // PocketBase record id once synced (nil = local-only)

    init(id: UUID = UUID(),
         name: String = "",
         logoData: Data? = nil,
         tagline: String = "",
         latitude: Double? = nil,
         longitude: Double? = nil,
         geofenceRadius: Double = 120,
         inviteCode: String = Club.makeInviteCode(),
         openInvite: Bool = true,
         planID: String = SeatPlan.freeID,
         pendingPlanID: String? = nil,
         getraenkewartEmail: String? = nil,
         remoteID: String? = nil) {
        self.id = id
        self.name = name
        self.logoData = logoData
        self.tagline = tagline
        self.latitude = latitude
        self.longitude = longitude
        self.geofenceRadius = geofenceRadius
        self.inviteCode = inviteCode
        self.openInvite = openInvite
        self.planID = planID
        self.pendingPlanID = pendingPlanID
        self.getraenkewartEmail = getraenkewartEmail
        self.remoteID = remoteID
    }

    static func makeInviteCode() -> String {
        let chars = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")  // no ambiguous chars
        return String((0..<6).map { _ in chars.randomElement()! })
    }

    // Tolerant decoding so older saved data (without invite fields) still loads.
    enum CodingKeys: String, CodingKey {
        case id, name, logoData, tagline, latitude, longitude, geofenceRadius, inviteCode, openInvite, planID, pendingPlanID, getraenkewartEmail, remoteID
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        logoData = try c.decodeIfPresent(Data.self, forKey: .logoData)
        tagline = try c.decode(String.self, forKey: .tagline)
        latitude = try c.decodeIfPresent(Double.self, forKey: .latitude)
        longitude = try c.decodeIfPresent(Double.self, forKey: .longitude)
        geofenceRadius = try c.decode(Double.self, forKey: .geofenceRadius)
        inviteCode = try c.decodeIfPresent(String.self, forKey: .inviteCode) ?? Club.makeInviteCode()
        openInvite = try c.decodeIfPresent(Bool.self, forKey: .openInvite) ?? true
        planID = try c.decodeIfPresent(String.self, forKey: .planID) ?? SeatPlan.freeID
        pendingPlanID = try c.decodeIfPresent(String.self, forKey: .pendingPlanID)
        getraenkewartEmail = try c.decodeIfPresent(String.self, forKey: .getraenkewartEmail)
        remoteID = try c.decodeIfPresent(String.self, forKey: .remoteID)
    }

    var logoImage: UIImage? {
        guard let logoData else { return nil }
        return UIImage(data: logoData)
    }
}

// MARK: - Seat plans (app licensing, billed by invoice)

struct SeatPlan: Identifiable, Hashable {
    let id: String
    let name: String
    let maxSeats: Int         // Int.max for enterprise / individual
    let monthlyPrice: Double  // 0 = free, -1 = individual pricing

    static let freeID = "free"

    var isFree: Bool { monthlyPrice == 0 }
    var isEnterprise: Bool { monthlyPrice < 0 }

    var priceLabel: String {
        if isFree { return "Kostenlos" }
        if isEnterprise { return "Individuell" }
        return String(format: "%.2f € / Monat", monthlyPrice)
    }

    /// Total billed once per year (12 months upfront).
    var yearlyTotal: Double { monthlyPrice * 12 }
}

enum SeatPlans {
    static let all: [SeatPlan] = [
        SeatPlan(id: "free",       name: "Kostenlos",              maxSeats: 5,      monthlyPrice: 0),
        SeatPlan(id: "s50",        name: "Bis 50 Plätze",          maxSeats: 50,     monthlyPrice: 1.99),
        SeatPlan(id: "s100",       name: "Bis 100 Plätze",         maxSeats: 100,    monthlyPrice: 3.49),
        SeatPlan(id: "s200",       name: "Bis 200 Plätze",         maxSeats: 200,    monthlyPrice: 6.49),
        SeatPlan(id: "s300",       name: "Bis 300 Plätze",         maxSeats: 300,    monthlyPrice: 9.99),
        SeatPlan(id: "s500",       name: "Bis 500 Plätze",         maxSeats: 500,    monthlyPrice: 16.99),
        SeatPlan(id: "enterprise", name: "Enterprise / Individuell", maxSeats: .max, monthlyPrice: -1),
    ]

    static func plan(id: String) -> SeatPlan { all.first { $0.id == id } ?? all[0] }

    /// Smallest plan that fits the given seat count.
    static func required(forSeats n: Int) -> SeatPlan {
        all.first { n <= $0.maxSeats } ?? all.last!
    }
}

// MARK: - App persisted state

struct AppData: Codable {
    var didOnboard: Bool = false
    var club: Club? = nil
    var drinks: [Drink] = []
    var members: [Member] = []
    var bookings: [Booking] = []
    var watchLinks: [WatchLink] = []
    var creditTx: [CreditTransaction] = []
    var currentMemberID: UUID? = nil
    var sync = SyncMeta()

    init() {}

    // Tolerant decoding so adding new fields never wipes existing saved data.
    enum CodingKeys: String, CodingKey {
        case didOnboard, club, drinks, members, bookings, watchLinks, creditTx, currentMemberID, sync
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        didOnboard = try c.decodeIfPresent(Bool.self, forKey: .didOnboard) ?? false
        club = try c.decodeIfPresent(Club.self, forKey: .club)
        drinks = try c.decodeIfPresent([Drink].self, forKey: .drinks) ?? []
        members = try c.decodeIfPresent([Member].self, forKey: .members) ?? []
        bookings = try c.decodeIfPresent([Booking].self, forKey: .bookings) ?? []
        watchLinks = try c.decodeIfPresent([WatchLink].self, forKey: .watchLinks) ?? []
        creditTx = try c.decodeIfPresent([CreditTransaction].self, forKey: .creditTx) ?? []
        currentMemberID = try c.decodeIfPresent(UUID.self, forKey: .currentMemberID)
        sync = try c.decodeIfPresent(SyncMeta.self, forKey: .sync) ?? SyncMeta()
    }
}

// MARK: - Sync metadata (offline-first bookkeeping)

/// Tracks what still needs pushing to the backend and when we last pulled.
/// Lives inside AppData so it survives restarts alongside the data it describes.
struct SyncMeta: Codable {
    /// Server timestamp of the last successful pull (for incremental sync).
    var lastPulledAt: Date? = nil
    /// Local ids of records mutated since the last successful push, per entity.
    var dirtyClub: Bool = false
    var dirtyMembers: Set<UUID> = []
    var dirtyDrinks: Set<UUID> = []
    var dirtyBookings: Set<UUID> = []
    var dirtyCreditTx: Set<UUID> = []
    var dirtyWatchLinks: Set<UUID> = []
    /// Records deleted locally that still need to be deleted on the backend.
    var pendingDeletes: [PendingDelete] = []

    init() {}

    // Tolerant decoding so future fields never break older saved data.
    enum CodingKeys: String, CodingKey {
        case lastPulledAt, dirtyClub, dirtyMembers, dirtyDrinks, dirtyBookings,
             dirtyCreditTx, dirtyWatchLinks, pendingDeletes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lastPulledAt = try c.decodeIfPresent(Date.self, forKey: .lastPulledAt)
        dirtyClub = try c.decodeIfPresent(Bool.self, forKey: .dirtyClub) ?? false
        dirtyMembers = try c.decodeIfPresent(Set<UUID>.self, forKey: .dirtyMembers) ?? []
        dirtyDrinks = try c.decodeIfPresent(Set<UUID>.self, forKey: .dirtyDrinks) ?? []
        dirtyBookings = try c.decodeIfPresent(Set<UUID>.self, forKey: .dirtyBookings) ?? []
        dirtyCreditTx = try c.decodeIfPresent(Set<UUID>.self, forKey: .dirtyCreditTx) ?? []
        dirtyWatchLinks = try c.decodeIfPresent(Set<UUID>.self, forKey: .dirtyWatchLinks) ?? []
        pendingDeletes = try c.decodeIfPresent([PendingDelete].self, forKey: .pendingDeletes) ?? []
    }
}

/// A record that was removed locally and still has to be deleted on the backend.
struct PendingDelete: Codable, Hashable {
    var collection: String   // PocketBase collection name
    var remoteID: String     // record id to delete
}

// MARK: - Seed catalog

enum DrinkCatalog {
    static var presets: [Drink] {
        [
            Drink(name: "Pils", emoji: "🍺", symbol: "mug.fill", price: 2.50,
                  category: .beer, tintHex: "#E8A317", sound: .beer),
            Drink(name: "Weizen", emoji: "🍺", symbol: "mug.fill", price: 3.20,
                  category: .beer, tintHex: "#D98A00",
                  sizes: [DrinkSize(label: "0,3 l", priceModifier: 0),
                          DrinkSize(label: "0,5 l", priceModifier: 0.80)],
                  sound: .beer),
            Drink(name: "Helles", emoji: "🍺", symbol: "mug.fill", price: 2.80,
                  category: .beer, tintHex: "#F0B429", sound: .beer),
            Drink(name: "Radler", emoji: "🍻", symbol: "mug.fill", price: 2.80,
                  category: .beer, tintHex: "#C9D92E", sound: .beer),
            Drink(name: "Sekt", emoji: "🥂", symbol: "wineglass.fill", price: 3.50,
                  category: .wine, tintHex: "#F6C453", sound: .sekt),
            Drink(name: "Weinschorle Weiß", emoji: "🥂", symbol: "wineglass.fill", price: 3.00,
                  category: .wine, tintHex: "#E3C770", sound: .sekt, iconSymbol: "wineglass.fill"),
            Drink(name: "Weinschorle Rot", emoji: "🍷", symbol: "wineglass.fill", price: 3.00,
                  category: .wine, tintHex: "#9B2D5E", sound: .sekt),
            Drink(name: "Weißwein", emoji: "🥂", symbol: "wineglass.fill", price: 3.50,
                  category: .wine, tintHex: "#E3C770",
                  sizes: [DrinkSize(label: "0,1 l", priceModifier: 0),
                          DrinkSize(label: "0,2 l", priceModifier: 1.50),
                          DrinkSize(label: "Flasche", priceModifier: 12.50)],
                  sound: .sekt, iconSymbol: "wineglass.fill"),
            Drink(name: "Rotwein", emoji: "🍷", symbol: "wineglass.fill", price: 3.50,
                  category: .wine, tintHex: "#7A1F47",
                  sizes: [DrinkSize(label: "0,1 l", priceModifier: 0),
                          DrinkSize(label: "0,2 l", priceModifier: 1.50),
                          DrinkSize(label: "Flasche", priceModifier: 12.50)],
                  sound: .sekt),
            Drink(name: "Sprudel", emoji: "💧", symbol: "waterbottle.fill", price: 1.50,
                  category: .soft, tintHex: "#2EC4F0"),
            Drink(name: "Süßer Sprudel", emoji: "🫧", symbol: "waterbottle.fill", price: 1.80,
                  category: .soft, tintHex: "#7AB8FF"),
            Drink(name: "Topfit", emoji: "🧃", symbol: "waterbottle.fill", price: 1.80,
                  category: .soft, tintHex: "#2EE6A6"),
            Drink(name: "Cola", emoji: "🥤", symbol: "cup.and.saucer.fill", price: 2.00,
                  category: .soft, tintHex: "#9B3B2E"),
            Drink(name: "Fanta", emoji: "🍊", symbol: "cup.and.saucer.fill", price: 2.00,
                  category: .soft, tintHex: "#F08A1D"),
            Drink(name: "Apfelschorle", emoji: "🍎", symbol: "cup.and.saucer.fill", price: 2.00,
                  category: .soft, tintHex: "#C4D92E"),
            Drink(name: "Kaffee", emoji: "☕️", symbol: "cup.and.saucer.fill", price: 1.50,
                  category: .hot, tintHex: "#6F4E37", sound: .coffee),
            Drink(name: "Bratwurst", emoji: "🌭", symbol: "carrot.fill", price: 2.50,
                  category: .snack, tintHex: "#B5651D", sound: .grill),
            Drink(name: "Brezel", emoji: "🥨", symbol: "carrot.fill", price: 1.50,
                  category: .snack, tintHex: "#8B5A2B"),
            Drink(name: "Chips", emoji: "🍟", symbol: "carrot.fill", price: 1.50,
                  category: .snack, tintHex: "#E0A82E")
        ]
    }
}

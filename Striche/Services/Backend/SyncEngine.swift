import Foundation
import Combine

// MARK: - Sync engine (offline-first push)
//
// Der lokale AppStore bleibt die Quelle der Wahrheit. Diese Engine schiebt die
// lokalen Daten best-effort ans PocketBase-Backend (Phase 3: Push). Alles läuft
// idempotent über die `remoteID`-Felder: Records ohne remoteID werden angelegt
// (POST), Records mit remoteID aktualisiert (PATCH). Schlägt etwas fehl
// (offline/Fehler), bleibt der lokale Stand unangetastet und der nächste Lauf
// holt es nach.
//
// Reihenfolge wegen der Relationen: club -> drinks -> bookings/creditTx/watchLinks.
// Mitglieder werden NICHT als User-Records gepusht (User registrieren sich selbst);
// referenzierende Records werden nur gepusht, wenn das Mitglied bereits eine
// remoteID hat (also schon einmal eingeloggt/registriert war).

@MainActor
final class SyncEngine: ObservableObject {
    @Published private(set) var isSyncing = false
    @Published private(set) var lastSyncedAt: Date?
    @Published private(set) var lastError: String?

    private let store: AppStore
    private let backend: BackendSession
    private let client: PocketBaseClient

    init(store: AppStore, backend: BackendSession, client: PocketBaseClient = PocketBaseClient()) {
        self.store = store
        self.backend = backend
        self.client = client
    }

    /// Fire-and-forget trigger for views/lifecycle hooks.
    func syncNow() {
        Task { await sync() }
    }

    /// Run a full push pass. No-op if not logged in or already running.
    func sync() async {
        guard !isSyncing, backend.isLoggedIn, let token = backend.token else { return }
        isSyncing = true
        lastError = nil
        defer { isSyncing = false }
        do {
            try await push(token: token)
            try await pull(token: token)
            lastSyncedAt = .now
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - Push

    private func push(token: String) async throws {
        guard let club = store.data.club, let me = store.currentMember else { return }

        // 1) Ensure the club exists remotely.
        let clubRID: String
        if let rid = club.remoteID {
            // Keep the remote club fields fresh.
            _ = try await client.update("clubs", id: rid, body: clubWrite(club),
                                        token: token, returning: ClubRecord.self)
            clubRID = rid
        } else if me.isAdmin {
            // Admin set up offline – create the club (+ admin membership) via the hook.
            guard let result = await backend.createClub(
                name: club.name, tagline: club.tagline, inviteCode: club.inviteCode,
                openInvite: club.openInvite, planID: club.planID,
                getraenkewartEmail: club.getraenkewartEmail) else { return }
            store.setClubRemoteID(result.club)
            if let uid = backend.userID { store.setCurrentMemberRemoteID(uid) }
            clubRID = result.club
        } else {
            // Non-admin without a synced club yet: nothing to push.
            return
        }

        // 2) Drinks (snapshot to avoid mutating while iterating).
        for (index, drink) in store.data.drinks.enumerated() {
            let body = drink.toWrite(clubID: clubRID, sortOrder: index)
            if let rid = drink.remoteID {
                _ = try await client.update("drinks", id: rid, body: body,
                                            token: token, returning: DrinkRecord.self)
            } else {
                let rec = try await client.create("drinks", body: body,
                                                  token: token, returning: DrinkRecord.self)
                store.setDrinkRemoteID(drink.id, rec.id)
            }
        }

        // Build local UUID -> remote id lookups (members + freshly-synced drinks).
        let memberRemote = Dictionary(uniqueKeysWithValues:
            store.data.members.compactMap { m in m.remoteID.map { (m.id, $0) } })
        let drinkRemote = Dictionary(uniqueKeysWithValues:
            store.data.drinks.compactMap { d in d.remoteID.map { (d.id, $0) } })

        // 3) Bookings – only for members that already have a backend user id.
        for booking in store.data.bookings {
            guard let memberRID = memberRemote[booking.memberID] else { continue }
            let body = BookingWrite(
                club: clubRID, member: memberRID, drink: drinkRemote[booking.drinkID],
                drink_name: booking.drinkName, size_label: booking.sizeLabel,
                price: booking.price, paid: booking.paid, date: booking.date)
            if let rid = booking.remoteID {
                _ = try await client.update("bookings", id: rid, body: body,
                                            token: token, returning: BookingRecord.self)
            } else {
                let rec = try await client.create("bookings", body: body,
                                                  token: token, returning: BookingRecord.self)
                store.setBookingRemoteID(booking.id, rec.id)
            }
        }

        // 4) Credit transactions.
        for tx in store.data.creditTx {
            guard let memberRID = memberRemote[tx.memberID] else { continue }
            let body = CreditTxWrite(
                club: clubRID, member: memberRID, amount: tx.amount,
                kind: tx.kind.backendValue, note: tx.note, date: tx.date)
            if let rid = tx.remoteID {
                _ = try await client.update("credit_transactions", id: rid, body: body,
                                            token: token, returning: CreditTxRecord.self)
            } else {
                let rec = try await client.create("credit_transactions", body: body,
                                                  token: token, returning: CreditTxRecord.self)
                store.setCreditTxRemoteID(tx.id, rec.id)
            }
        }

        // 5) Watch links – need both booker and watcher synced.
        for link in store.data.watchLinks {
            guard let bookerRID = memberRemote[link.bookerID],
                  let watcherRID = memberRemote[link.watcherID] else { continue }
            let body = WatchLinkWrite(
                club: clubRID, booker: bookerRID, watcher: watcherRID,
                status: link.status.rawValue)
            if let rid = link.remoteID {
                _ = try await client.update("watch_links", id: rid, body: body,
                                            token: token, returning: WatchLinkRecord.self)
            } else {
                let rec = try await client.create("watch_links", body: body,
                                                  token: token, returning: WatchLinkRecord.self)
                store.setWatchLinkRemoteID(link.id, rec.id)
            }
        }
    }

    // MARK: - Pull
    //
    // Holt den Server-Stand der Vereine des Users ins lokale Model (upsert per
    // remoteID). Reihenfolge wegen Relationen: club -> members (via memberships,
    // expand user) -> drinks -> bookings/creditTx/watchLinks. Remote ist für
    // bereits synchronisierte Records autoritativ; rein lokale (noch ohne
    // remoteID) bleiben unangetastet und werden beim nächsten Push hochgeladen.

    private func pull(token: String) async throws {
        // 1) Club (scoped rule liefert nur die Vereine des Users).
        let clubs: PBList<ClubRecord> = try await client.list("clubs", token: token, perPage: 1)
        guard let rc = clubs.items.first else { return }
        let clubRID = rc.id
        store.upsertPulledClub(clubFromRecord(rc))

        let filter = "club=\"\(clubRID)\""

        // 2) Members via memberships (expand user).
        let memberships: PBList<MembershipExpand> = try await client.list(
            "memberships", token: token, filter: filter, expand: "user", perPage: 500)
        for m in memberships.items {
            guard let u = m.expand?.user else { continue }
            var member = Member(name: (u.name?.isEmpty == false ? u.name! : u.email),
                                email: u.email, isAdmin: m.role == "admin",
                                emoji: (u.emoji?.isEmpty == false ? u.emoji! : "🧑"))
            member.remoteID = u.id
            store.upsertPulledMember(member)
        }
        let memberByRemote = Dictionary(uniqueKeysWithValues:
            store.data.members.compactMap { mb in mb.remoteID.map { ($0, mb.id) } })

        // 3) Drinks.
        let drinks: PBList<DrinkRecord> = try await client.list(
            "drinks", token: token, filter: filter, sort: "sort_order", perPage: 500)
        for d in drinks.items {
            var local = d.toLocalDrink()
            local.remoteID = d.id
            store.upsertPulledDrink(local)
        }
        let drinkByRemote = Dictionary(uniqueKeysWithValues:
            store.data.drinks.compactMap { dr in dr.remoteID.map { ($0, dr.id) } })

        // 4) Bookings.
        let bookings: PBList<BookingRecord> = try await client.list(
            "bookings", token: token, filter: filter, sort: "-date", perPage: 500)
        for b in bookings.items {
            guard let memberID = memberByRemote[b.member] else { continue }
            var local = Booking(
                memberID: memberID,
                drinkID: b.drink.flatMap { drinkByRemote[$0] } ?? UUID(),
                drinkName: b.drink_name ?? "",
                sizeLabel: b.size_label,
                price: b.price ?? 0,
                date: b.date ?? .now,
                paid: b.paid ?? false)
            local.remoteID = b.id
            store.upsertPulledBooking(local)
        }

        // 5) Credit transactions.
        let txs: PBList<CreditTxRecord> = try await client.list(
            "credit_transactions", token: token, filter: filter, perPage: 500)
        for t in txs.items {
            guard let memberID = memberByRemote[t.member],
                  let kind = CreditKind(backend: t.kind) else { continue }
            var local = CreditTransaction(
                memberID: memberID, amount: t.amount ?? 0, kind: kind,
                date: t.date ?? .now, note: t.note)
            local.remoteID = t.id
            store.upsertPulledCreditTx(local)
        }

        // 6) Watch links.
        let links: PBList<WatchLinkRecord> = try await client.list(
            "watch_links", token: token, filter: filter, perPage: 500)
        for w in links.items {
            guard let booker = memberByRemote[w.booker],
                  let watcher = memberByRemote[w.watcher] else { continue }
            var local = WatchLink(
                bookerID: booker, watcherID: watcher,
                status: WatchStatus(backend: w.status), created: w.created ?? .now)
            local.remoteID = w.id
            store.upsertPulledWatchLink(local)
        }

        store.markPulled(Date())
    }

    private func clubFromRecord(_ r: ClubRecord) -> Club {
        Club(
            name: r.name,
            tagline: r.tagline ?? "",
            latitude: r.latitude,
            longitude: r.longitude,
            geofenceRadius: r.geofence_radius ?? 120,
            inviteCode: r.invite_code ?? Club.makeInviteCode(),
            openInvite: r.open_invite ?? true,
            planID: r.plan_id ?? SeatPlan.freeID,
            pendingPlanID: r.pending_plan_id,
            getraenkewartEmail: r.getraenkewart_email,
            remoteID: r.id
        )
    }

    private func clubWrite(_ club: Club) -> ClubWrite {
        ClubWrite(
            name: club.name,
            tagline: club.tagline,
            invite_code: club.inviteCode,
            open_invite: club.openInvite,
            latitude: club.latitude,
            longitude: club.longitude,
            geofence_radius: club.geofenceRadius,
            plan_id: club.planID,
            pending_plan_id: club.pendingPlanID,
            getraenkewart_email: club.getraenkewartEmail
        )
    }
}

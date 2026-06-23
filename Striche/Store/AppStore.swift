import Foundation
import SwiftUI
import CryptoKit

@MainActor
final class AppStore: ObservableObject {
    @Published var data: AppData {
        didSet { save() }
    }

    /// Invite code captured from an opened deep link (striche://join?code=XXXXXX),
    /// not persisted – drives the auto-join during registration.
    @Published var pendingInviteCode: String?

    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("striche_data.json")
    }()

    init() {
        if let raw = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(AppData.self, from: raw) {
            self.data = decoded
        } else {
            self.data = AppData()
        }
        // Heal `paid` flags for existing data (e.g. credit added before reconcile existed).
        for member in data.members { reconcile(member: member) }
        // Give the white-wine spritzer a proper white-wine glass icon in older data.
        for i in data.drinks.indices where data.drinks[i].iconSymbol == nil
            && data.drinks[i].name.localizedCaseInsensitiveContains("Weinschorle Weiß") {
            data.drinks[i].iconSymbol = "wineglass.fill"
        }
        migrateWineSplit()
    }

    /// Older data only had a generic "Wein". Rename it to "Rotwein" (keeps bookings)
    /// and add a "Weißwein" so both are available.
    private func migrateWineSplit() {
        guard let idx = data.drinks.firstIndex(where: { $0.name == "Wein" }) else { return }
        var red = data.drinks[idx]
        red.name = "Rotwein"
        data.drinks[idx] = red
        if !data.drinks.contains(where: { $0.name == "Weißwein" }) {
            let white = Drink(name: "Weißwein", emoji: "🥂", symbol: "wineglass.fill",
                              price: red.price, category: .wine, tintHex: "#E3C770",
                              sizes: red.sizes, sound: .sekt, iconSymbol: "wineglass.fill")
            data.drinks.insert(white, at: idx)
        }
    }

    // MARK: Persistence
    private func save() {
        guard let raw = try? JSONEncoder().encode(data) else { return }
        try? raw.write(to: fileURL, options: .atomic)
    }

    // MARK: Convenience accessors
    var club: Club? { data.club }
    var drinks: [Drink] { data.drinks }
    var members: [Member] { data.members }
    var bookings: [Booking] { data.bookings }

    var currentMember: Member? {
        guard let id = data.currentMemberID else { return nil }
        return data.members.first { $0.id == id }
    }

    var isLoggedIn: Bool { currentMember != nil }

    // MARK: Onboarding
    func completeOnboarding() { data.didOnboard = true }

    // MARK: Club setup (admin)
    func createClub(name: String, tagline: String, logo: Data?, inviteCode: String? = nil) {
        var club = data.club ?? Club()
        club.name = name
        club.tagline = tagline
        if let logo { club.logoData = logo }
        if let inviteCode { club.inviteCode = inviteCode }
        data.club = club
    }

    /// Generate a fresh invite code for the club (revokes the previous link).
    func regenerateInviteCode() {
        guard var club = data.club else { return }
        club.inviteCode = Club.makeInviteCode()
        data.club = club
    }

    func setOpenInvite(_ on: Bool) {
        guard var club = data.club else { return }
        club.openInvite = on
        data.club = club
    }

    /// Email address the "Getränke leer melden" reports are sent to.
    func setGetraenkewartEmail(_ email: String?) {
        guard var club = data.club else { return }
        let trimmed = email?.trimmingCharacters(in: .whitespacesAndNewlines)
        club.getraenkewartEmail = (trimmed?.isEmpty == true) ? nil : trimmed
        data.club = club
    }

    /// Persist a new order of the drink tiles.
    func reorderDrinks(from source: IndexSet, to destination: Int) {
        data.drinks.move(fromOffsets: source, toOffset: destination)
    }

    /// Shareable invite link for the club. Uses the https Universal-Link form so it
    /// also works for people who don't have the app yet (they land on the web page
    /// striche-app.de/join, which then hands off into the app or shows the App Store).
    var inviteLink: String {
        let code = data.club?.inviteCode ?? ""
        return "https://striche-app.de/join?code=\(code)"
    }

    /// Ready-to-send WhatsApp invite message including the link.
    var inviteMessage: String {
        let name = data.club?.name ?? "unserem Verein"
        return """
        🍻 Tritt \(name) auf Striche bei!
        Mit dieser App buchst du deine Getränke ganz einfach selbst.

        👉 \(inviteLink)

        Einfach öffnen, registrieren – fertig. Du wirst automatisch mit dem Verein verbunden.
        """
    }

    /// wa.me deep link that opens WhatsApp with the invite text prefilled.
    var whatsAppShareURL: URL? {
        let text = inviteMessage.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "https://wa.me/?text=\(text)")
    }

    /// Capture an opened invite URL. Accepts both the custom scheme
    /// (striche://join?code=XXXXXX) and the https Universal Link
    /// (https://striche-app.de/join?code=XXXXXX).
    func handleInviteURL(_ url: URL) {
        let scheme = url.scheme?.lowercased()
        let isCustom = scheme == "striche"
        let isUniversal = (scheme == "https" || scheme == "http")
            && url.host?.lowercased() == "striche-app.de"
            && url.path.lowercased().hasPrefix("/join")
        guard isCustom || isUniversal else { return }
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if let code = comps?.queryItems?.first(where: { $0.name == "code" })?.value, !code.isEmpty {
            pendingInviteCode = code.uppercased()
        }
    }

    /// True if the captured invite code matches the current club's open invite.
    var pendingInviteIsValid: Bool {
        guard let code = pendingInviteCode, let club = data.club, club.openInvite else { return false }
        return code.caseInsensitiveCompare(club.inviteCode) == .orderedSame
    }

    func setSeedDrinks(_ drinks: [Drink]) { data.drinks = drinks }

    func addDrink(_ drink: Drink) { data.drinks.append(drink) }

    func updateDrink(_ drink: Drink) {
        if let idx = data.drinks.firstIndex(where: { $0.id == drink.id }) {
            data.drinks[idx] = drink
        }
    }

    func removeDrink(_ drink: Drink) { data.drinks.removeAll { $0.id == drink.id } }

    func updateClubLocation(lat: Double, lon: Double, radius: Double) {
        guard var club = data.club else { return }
        club.latitude = lat
        club.longitude = lon
        club.geofenceRadius = radius
        data.club = club
    }

    // MARK: Watch links (notify-on-booking with consent)

    /// Current member asks `watcher` to be notified when current member books.
    func requestWatch(watcher: Member) {
        guard let me = currentMember, me.id != watcher.id else { return }
        if let idx = data.watchLinks.firstIndex(where: { $0.bookerID == me.id && $0.watcherID == watcher.id }) {
            // Re-asking after a decline resets to pending.
            if data.watchLinks[idx].status == .declined {
                data.watchLinks[idx].status = .pending
                data.watchLinks[idx].created = .now
            }
            return
        }
        data.watchLinks.append(WatchLink(bookerID: me.id, watcherID: watcher.id))
    }

    /// Current member removes a watcher they previously chose.
    func removeWatch(watcherID: UUID) {
        guard let me = currentMember else { return }
        data.watchLinks.removeAll { $0.bookerID == me.id && $0.watcherID == watcherID }
    }

    /// Status of a watcher chosen by the current member.
    func watchStatus(watcherID: UUID) -> WatchStatus? {
        guard let me = currentMember else { return nil }
        return data.watchLinks.first { $0.bookerID == me.id && $0.watcherID == watcherID }?.status
    }

    /// Requests where the current member is asked to be a watcher and hasn't decided.
    func incomingRequests() -> [WatchLink] {
        guard let me = currentMember else { return [] }
        return data.watchLinks.filter { $0.watcherID == me.id && $0.status == .pending }
    }

    func incomingRequestCount() -> Int { incomingRequests().count }

    func acceptWatch(_ link: WatchLink) {
        if let idx = data.watchLinks.firstIndex(where: { $0.id == link.id }) {
            data.watchLinks[idx].status = .accepted
        }
    }

    func declineWatch(_ link: WatchLink) {
        if let idx = data.watchLinks.firstIndex(where: { $0.id == link.id }) {
            data.watchLinks[idx].status = .declined
        }
    }

    /// Members who accepted to be notified when `bookerID` books.
    func acceptedWatchers(of bookerID: UUID) -> [Member] {
        let ids = data.watchLinks
            .filter { $0.bookerID == bookerID && $0.status == .accepted }
            .map { $0.watcherID }
        return data.members.filter { ids.contains($0.id) }
    }

    // MARK: Members
    @discardableResult
    func inviteMember(name: String, email: String, isAdmin: Bool = false) -> Member {
        let email = email.lowercased()
        if let existing = data.members.first(where: { $0.email == email }) { return existing }
        let m = Member(name: name.isEmpty ? email : name, email: email, isAdmin: isAdmin,
                       emoji: AvatarPool.random())
        data.members.append(m)
        return m
    }

    func removeMember(_ member: Member) {
        data.members.removeAll { $0.id == member.id }
    }

    /// Bulk import from "name,email" lines (Excel/CSV paste).
    func importMembers(csv: String) -> Int {
        var count = 0
        for line in csv.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: ",", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            guard !parts.isEmpty else { continue }
            if parts.count == 2, parts[1].contains("@") {
                inviteMember(name: parts[0], email: parts[1])
                count += 1
            } else if parts.count == 1, parts[0].contains("@") {
                inviteMember(name: "", email: parts[0])
                count += 1
            }
        }
        return count
    }

    // MARK: Auth
    enum AuthResult: Equatable {
        case success
        case notWhitelisted          // email not in member list
        case wrongPassword
        case alreadyRegistered
    }

    private func hash(_ pw: String) -> String {
        let digest = SHA256.hash(data: Data(pw.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Member self-registration. Works if the club whitelisted the email OR a valid
    /// open invite link was used (auto-joins the club).
    func register(email: String, password: String, name: String) -> AuthResult {
        let email = email.lowercased()
        if let idx = data.members.firstIndex(where: { $0.email == email }) {
            if data.members[idx].passwordHash != nil { return .alreadyRegistered }
            data.members[idx].passwordHash = hash(password)
            if !name.isEmpty { data.members[idx].name = name }
            data.currentMemberID = data.members[idx].id
            return .success
        }
        // Not whitelisted – allow join via a valid invite link.
        guard pendingInviteIsValid else { return .notWhitelisted }
        var member = Member(name: name.isEmpty ? email : name, email: email,
                            emoji: AvatarPool.random())
        member.passwordHash = hash(password)
        data.members.append(member)
        data.currentMemberID = member.id
        pendingInviteCode = nil
        return .success
    }

    func login(email: String, password: String) -> AuthResult {
        let email = email.lowercased()
        guard let member = data.members.first(where: { $0.email == email }) else {
            return .notWhitelisted
        }
        guard let stored = member.passwordHash else { return .wrongPassword }
        guard stored == hash(password) else { return .wrongPassword }
        data.currentMemberID = member.id
        return .success
    }

    func logout() { data.currentMemberID = nil }

    /// Adopt a backend-validated invite join on a fresh device (no local club yet).
    /// The invite code was already verified server-side by `/api/striche/join`, so we
    /// just establish the local session: match/create the member by backend user id,
    /// store the password hash for later offline login, and make them the current user.
    /// The club + roster + drinks then arrive via the subsequent pull.
    func adoptRemoteJoin(remoteUserID: String, email: String, password: String, name: String) {
        let email = email.lowercased()
        if let idx = data.members.firstIndex(where: { $0.remoteID == remoteUserID }) {
            data.members[idx].passwordHash = hash(password)
            if !name.isEmpty { data.members[idx].name = name }
            data.currentMemberID = data.members[idx].id
        } else if let idx = data.members.firstIndex(where: { $0.email == email }) {
            data.members[idx].remoteID = remoteUserID
            data.members[idx].passwordHash = hash(password)
            data.currentMemberID = data.members[idx].id
        } else {
            var member = Member(name: name.isEmpty ? email : name, email: email,
                                emoji: AvatarPool.random())
            member.remoteID = remoteUserID
            member.passwordHash = hash(password)
            data.members.append(member)
            data.currentMemberID = member.id
        }
        pendingInviteCode = nil
    }

    /// Establish a local session for a backend user authenticated via OAuth (Google).
    /// Like `adoptRemoteJoin` but without a password hash (OAuth users have none –
    /// they re-authenticate via the stored token). Matches by backend id, then email.
    func adoptBackendUser(remoteUserID: String, email: String, name: String) {
        let email = email.lowercased()
        if let idx = data.members.firstIndex(where: { $0.remoteID == remoteUserID }) {
            if !name.isEmpty { data.members[idx].name = name }
            data.currentMemberID = data.members[idx].id
        } else if let idx = data.members.firstIndex(where: { $0.email == email }) {
            data.members[idx].remoteID = remoteUserID
            data.currentMemberID = data.members[idx].id
        } else {
            var member = Member(name: name.isEmpty ? email : name, email: email,
                                emoji: AvatarPool.random())
            member.remoteID = remoteUserID
            data.members.append(member)
            data.currentMemberID = member.id
        }
        pendingInviteCode = nil
    }

    /// Store the backend (PocketBase) user id on the current member for later sync.
    func setCurrentMemberRemoteID(_ remoteID: String) {
        guard let id = data.currentMemberID,
              let idx = data.members.firstIndex(where: { $0.id == id }) else { return }
        guard data.members[idx].remoteID != remoteID else { return }
        data.members[idx].remoteID = remoteID
    }

    /// Change the current member's e-mail locally (login identity). Only used for
    /// local-only members without a backend account – for synced members the
    /// backend confirm-email-change flow is authoritative and the next pull updates
    /// the local copy.
    func updateCurrentMemberEmail(_ newEmail: String) {
        guard let id = data.currentMemberID,
              let idx = data.members.firstIndex(where: { $0.id == id }) else { return }
        let clean = newEmail.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        data.members[idx].email = clean
    }

    /// Store the backend ids returned by the club create/join hooks.
    func setClubRemoteID(_ remoteID: String) {
        guard var club = data.club, club.remoteID != remoteID else { return }
        club.remoteID = remoteID
        data.club = club
    }

    /// Persist the backend record id for a synced drink/booking/credit/watch entity.
    func setDrinkRemoteID(_ localID: UUID, _ remoteID: String) {
        if let i = data.drinks.firstIndex(where: { $0.id == localID }) { data.drinks[i].remoteID = remoteID }
    }
    func setBookingRemoteID(_ localID: UUID, _ remoteID: String) {
        if let i = data.bookings.firstIndex(where: { $0.id == localID }) { data.bookings[i].remoteID = remoteID }
    }
    func setCreditTxRemoteID(_ localID: UUID, _ remoteID: String) {
        if let i = data.creditTx.firstIndex(where: { $0.id == localID }) { data.creditTx[i].remoteID = remoteID }
    }
    func setWatchLinkRemoteID(_ localID: UUID, _ remoteID: String) {
        if let i = data.watchLinks.firstIndex(where: { $0.id == localID }) { data.watchLinks[i].remoteID = remoteID }
    }

    // MARK: Pull upserts (remote -> local, matched by remoteID)

    func markPulled(_ date: Date) { data.sync.lastPulledAt = date }

    /// Adopt/refresh the club from the backend. Keeps the local id + logo.
    func upsertPulledClub(_ remote: Club) {
        guard var local = data.club else { data.club = remote; return }
        guard local.remoteID == nil || local.remoteID == remote.remoteID else { return }
        local.name = remote.name
        local.tagline = remote.tagline
        local.inviteCode = remote.inviteCode
        local.openInvite = remote.openInvite
        local.latitude = remote.latitude
        local.longitude = remote.longitude
        local.geofenceRadius = remote.geofenceRadius
        local.planID = remote.planID
        local.pendingPlanID = remote.pendingPlanID
        local.getraenkewartEmail = remote.getraenkewartEmail
        local.remoteID = remote.remoteID
        data.club = local
    }

    func upsertPulledMember(_ remote: Member) {
        if let i = data.members.firstIndex(where: { $0.remoteID != nil && $0.remoteID == remote.remoteID }) {
            data.members[i].name = remote.name
            data.members[i].email = remote.email
            data.members[i].emoji = remote.emoji
            data.members[i].isAdmin = remote.isAdmin
        } else {
            data.members.append(remote)
        }
    }

    /// Backend owns name/price/emoji/tint/sizes/icon; local keeps category/sound/symbol.
    func upsertPulledDrink(_ remote: Drink) {
        if let i = data.drinks.firstIndex(where: { $0.remoteID != nil && $0.remoteID == remote.remoteID }) {
            data.drinks[i].name = remote.name
            data.drinks[i].emoji = remote.emoji
            data.drinks[i].price = remote.price
            data.drinks[i].tintHex = remote.tintHex
            data.drinks[i].sizes = remote.sizes
            data.drinks[i].iconSymbol = remote.iconSymbol
        } else {
            data.drinks.append(remote)
        }
    }

    func upsertPulledBooking(_ remote: Booking) {
        if let i = data.bookings.firstIndex(where: { $0.remoteID != nil && $0.remoteID == remote.remoteID }) {
            var b = remote; b.id = data.bookings[i].id
            data.bookings[i] = b
        } else {
            data.bookings.insert(remote, at: 0)
        }
    }

    func upsertPulledCreditTx(_ remote: CreditTransaction) {
        if let i = data.creditTx.firstIndex(where: { $0.remoteID != nil && $0.remoteID == remote.remoteID }) {
            var t = remote; t.id = data.creditTx[i].id
            data.creditTx[i] = t
        } else {
            data.creditTx.append(remote)
        }
    }

    func upsertPulledWatchLink(_ remote: WatchLink) {
        if let i = data.watchLinks.firstIndex(where: { $0.remoteID != nil && $0.remoteID == remote.remoteID }) {
            var w = remote; w.id = data.watchLinks[i].id
            data.watchLinks[i] = w
        } else {
            data.watchLinks.append(remote)
        }
    }

    /// Update the current member's avatar: pick an emoji (clears any photo) or set a custom photo.
    func updateAvatar(emoji: String? = nil, photo: Data? = nil) {
        guard let id = data.currentMemberID,
              let idx = data.members.firstIndex(where: { $0.id == id }) else { return }
        if let photo {
            data.members[idx].avatarData = photo
        } else if let emoji {
            data.members[idx].emoji = emoji
            data.members[idx].avatarData = nil
        }
    }

    /// Used after admin finishes setup so they land in the app as a member too.
    func setCurrentMember(_ id: UUID) { data.currentMemberID = id }

    // MARK: Bookings
    func book(drink: Drink, size: DrinkSize?) {
        guard let member = currentMember else { return }
        let price = drink.price + (size?.priceModifier ?? 0)
        let b = Booking(memberID: member.id,
                        drinkID: drink.id,
                        drinkName: drink.name,
                        sizeLabel: size?.label,
                        price: price)
        data.bookings.insert(b, at: 0)
        reconcile(member: member)
    }

    /// Undo the most recent booking of a drink by current member (double-tap mistakes).
    func undoLastBooking(of drink: Drink) {
        guard let member = currentMember else { return }
        if let idx = data.bookings.firstIndex(where: {
            $0.memberID == member.id && $0.drinkID == drink.id
                && Calendar.current.isDateInToday($0.date)
        }) {
            data.bookings.remove(at: idx)
        }
        reconcile(member: member)
    }

    func bookings(for member: Member) -> [Booking] {
        data.bookings.filter { $0.memberID == member.id }
    }

    // MARK: Credit / balance ledger

    func creditTransactions(for member: Member) -> [CreditTransaction] {
        data.creditTx.filter { $0.memberID == member.id }.sorted { $0.date > $1.date }
    }

    /// Raw account balance: positive = Guthaben, negative = offener Deckel.
    func balance(for member: Member) -> Double {
        let credits = data.creditTx.filter { $0.memberID == member.id }.reduce(0) { $0 + $1.amount }
        let spent = bookings(for: member).reduce(0) { $0 + $1.price }
        return credits - spent
    }

    /// Remaining prepaid credit (0 if the member owes money).
    func credit(for member: Member) -> Double { max(0, balance(for: member)) }

    /// Outstanding amount the member owes (0 if in credit).
    func total(for member: Member) -> Double { max(0, -balance(for: member)) }

    /// Admin loads credit onto a member's account (e.g. cash payment).
    func topUp(member: Member, amount: Double, note: String? = nil) {
        guard amount > 0 else { return }
        data.creditTx.append(CreditTransaction(memberID: member.id, amount: amount,
                                               kind: .topUp,
                                               note: note ?? "Guthaben aufgeladen"))
        reconcile(member: member)
    }

    /// Marks bookings paid (oldest first) as far as the member's credit covers them.
    /// Keeps the `paid` flag in sync with the balance after bookings or top-ups.
    private func reconcile(member: Member) {
        let credits = data.creditTx.filter { $0.memberID == member.id }.reduce(0) { $0 + $1.amount }
        let order = data.bookings.enumerated()
            .filter { $0.element.memberID == member.id }
            .sorted { $0.element.date < $1.element.date }
        var spent = 0.0
        for (idx, booking) in order {
            spent += booking.price
            data.bookings[idx].paid = spent <= credits + 0.0001
        }
    }

    /// Number of times the member booked this drink TODAY (paid or not).
    func count(of drink: Drink, for member: Member) -> Int {
        data.bookings.filter {
            $0.memberID == member.id && $0.drinkID == drink.id
                && Calendar.current.isDateInToday($0.date)
        }.count
    }

    /// Total amount owed across all members.
    var grandTotal: Double {
        data.members.reduce(0) { $0 + total(for: $1) }
    }

    /// Total prepaid credit held across all members.
    var grandCredit: Double {
        data.members.reduce(0) { $0 + credit(for: $1) }
    }

    /// Settle the open tab in cash: clears the debt and marks bookings paid.
    func markPaid(member: Member) {
        let owed = total(for: member)
        if owed > 0 {
            data.creditTx.append(CreditTransaction(memberID: member.id, amount: owed,
                                                   kind: .settlement,
                                                   note: "Deckel bar bezahlt"))
        }
        reconcile(member: member)
    }

    func memberName(_ id: UUID) -> String {
        data.members.first { $0.id == id }?.name ?? "Unbekannt"
    }

    func memberEmoji(_ id: UUID) -> String {
        data.members.first { $0.id == id }?.emoji ?? "🧑"
    }

    // MARK: - Statistics & reports

    /// Years that have at least one booking or credit transaction, newest first.
    var yearsWithData: [Int] {
        let cal = Calendar.current
        let years = Set(data.bookings.map { cal.component(.year, from: $0.date) }
                        + data.creditTx.map { cal.component(.year, from: $0.date) })
        return years.sorted(by: >)
    }

    /// Booked revenue per month (index 0 = Januar) for a given year.
    func monthlyRevenue(year: Int) -> [Double] {
        let cal = Calendar.current
        var months = Array(repeating: 0.0, count: 12)
        for b in data.bookings where cal.component(.year, from: b.date) == year {
            months[cal.component(.month, from: b.date) - 1] += b.price
        }
        return months
    }

    /// Money actually received per month (top-ups + settlements) for a given year.
    func monthlyPaid(year: Int) -> [Double] {
        let cal = Calendar.current
        var months = Array(repeating: 0.0, count: 12)
        for t in data.creditTx where cal.component(.year, from: t.date) == year {
            months[cal.component(.month, from: t.date) - 1] += t.amount
        }
        return months
    }

    /// All bookings within a given month/year.
    func bookings(year: Int, month: Int) -> [Booking] {
        let cal = Calendar.current
        return data.bookings.filter {
            cal.component(.year, from: $0.date) == year
                && cal.component(.month, from: $0.date) == month
        }
    }

    /// Aggregated report positions (e.g. "Pils · 0,3 l") for a month/year.
    func reportPositions(year: Int, month: Int) -> [ReportPosition] {
        let items = bookings(year: year, month: month)
        let groups = Dictionary(grouping: items) { b in
            b.drinkName + (b.sizeLabel.map { " · \($0)" } ?? "")
        }
        return groups.map { key, list in
            let total = list.reduce(0) { $0 + $1.price }
            let paid = list.filter { $0.paid }.reduce(0) { $0 + $1.price }
            return ReportPosition(key: key,
                                  name: list.first?.drinkName ?? key,
                                  sizeLabel: list.first?.sizeLabel,
                                  count: list.count,
                                  unitPrice: list.first?.price ?? 0,
                                  total: total,
                                  paidTotal: paid,
                                  openTotal: total - paid)
        }.sorted { $0.total > $1.total }
    }

    // MARK: - Seat plan / licensing (billed by invoice)

    /// Number of seats currently in use (members in the club).
    var usedSeats: Int { data.members.count }

    /// The plan the club is licensed for right now.
    var activePlan: SeatPlan { SeatPlans.plan(id: data.club?.planID ?? SeatPlan.freeID) }

    /// Smallest plan that would fit the current member count.
    var requiredPlan: SeatPlan { SeatPlans.required(forSeats: usedSeats) }

    /// Remaining free seats within the active plan (0 if overbooked).
    var seatsRemaining: Int { max(0, activePlan.maxSeats - usedSeats) }

    /// True when the club has more members than its active plan allows.
    var needsUpgrade: Bool { usedSeats > activePlan.maxSeats }

    /// A plan that was ordered but whose invoice is still open.
    var pendingPlan: SeatPlan? {
        guard let id = data.club?.pendingPlanID else { return nil }
        return SeatPlans.plan(id: id)
    }

    /// Order a plan. Paid plans are unlocked immediately (trust-based, invoice
    /// is sent manually); the pending flag marks the open invoice. Enterprise
    /// only records a contact request without changing the active plan.
    func requestPlan(_ plan: SeatPlan) {
        guard var club = data.club else { return }
        if plan.isEnterprise {
            club.pendingPlanID = plan.id
        } else {
            club.planID = plan.id
            club.pendingPlanID = plan.isFree ? nil : plan.id
        }
        data.club = club
    }

    /// Marks the open invoice as settled (used later by the owner dashboard).
    func markPlanPaid() {
        guard var club = data.club else { return }
        club.pendingPlanID = nil
        data.club = club
    }

    // MARK: Reset (dev / settings)
    func resetEverything() {
        data = AppData()
    }
}

/// One aggregated line in the monthly Kassenwart report.
struct ReportPosition: Identifiable {
    var id: String { key }
    let key: String
    let name: String
    let sizeLabel: String?
    let count: Int
    let unitPrice: Double
    let total: Double
    let paidTotal: Double
    let openTotal: Double
}

enum AvatarPool {
    // Fun, characterful avatars only – no plain default faces.
    static let all = [
        "🧙","🧙‍♀️","🦸","🦸‍♀️","🦹","🦹‍♀️","🥷","🧛","🧛‍♀️","🧝","🧝‍♀️",
        "🧚","🧚‍♀️","🧜","🧜‍♀️","🧞","🤠","🤴","👸","🦄","🐉","🐲",
        "👽","👾","🤖","👻","💀","🎃","🤡","🥳","😎","🤩","🥸","🤓",
        "🦊","🐺","🦁","🐯","🐻","🐼","🐨","🐸","🦅","🦉","🦇","🐙","🦖","🦕"
    ]
    static func random() -> String { all.randomElement() ?? "🧙" }
}

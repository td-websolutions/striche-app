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

    // MARK: Convenience accessors (scoped to the current club)

    /// Id of the club currently shown in the booking view.
    private var cc: UUID? { data.currentClubID }

    /// The currently selected club.
    var club: Club? { data.clubs.first { $0.id == cc } }

    /// Find a local club by its backend record id (after a pull).
    func clubByRemoteID(_ remoteID: String) -> Club? {
        data.clubs.first { $0.remoteID == remoteID }
    }

    /// All clubs the logged-in person is a member of (by identity e-mail).
    var myClubs: [Club] {
        guard let email = data.identityEmail else { return [] }
        let ids = Set(data.members.filter { $0.email == email }.compactMap { $0.clubID })
        return data.clubs.filter { ids.contains($0.id) }
    }

    var drinks: [Drink] { data.drinks.filter { $0.clubID == cc } }
    var members: [Member] { data.members.filter { $0.clubID == cc } }
    var bookings: [Booking] { data.bookings.filter { $0.clubID == cc } }

    /// Credit transactions of the current club.
    private var clubCreditTx: [CreditTransaction] { data.creditTx.filter { $0.clubID == cc } }
    /// Watch links of the current club.
    private var clubWatchLinks: [WatchLink] { data.watchLinks.filter { $0.clubID == cc } }

    /// The logged-in person's member record within the current club.
    var currentMember: Member? {
        guard let cc else { return nil }
        if let id = data.currentMemberID,
           let m = data.members.first(where: { $0.id == id && $0.clubID == cc }) {
            return m
        }
        if let email = data.identityEmail {
            return data.members.first { $0.clubID == cc && $0.email == email }
        }
        return nil
    }

    /// A person is "logged in" once an identity is established, even before a club
    /// is picked (RootView then routes to club selection / the no-club screen).
    var isLoggedIn: Bool { data.identityEmail != nil }

    /// If the user belongs to exactly one club and none is selected yet, enter it.
    /// (A choice screen is only shown when several Vereine are available.)
    func autoSelectClubIfSingle() {
        guard data.currentClubID == nil, myClubs.count == 1, let only = myClubs.first else { return }
        switchClub(only.id)
    }

    /// Switch the active club. Recomputes the current member within that club.
    func switchClub(_ id: UUID) {
        guard data.clubs.contains(where: { $0.id == id }) else { return }
        data.currentClubID = id
        if let email = data.identityEmail,
           let m = data.members.first(where: { $0.clubID == id && $0.email == email }) {
            data.currentMemberID = m.id
        } else {
            data.currentMemberID = nil
        }
    }

    // MARK: Onboarding
    func completeOnboarding() { data.didOnboard = true }

    // MARK: Club setup (admin)

    /// Mutate the currently selected club in place.
    private func mutateCurrentClub(_ change: (inout Club) -> Void) {
        guard let cc, let idx = data.clubs.firstIndex(where: { $0.id == cc }) else { return }
        change(&data.clubs[idx])
    }

    /// Wizard onboarding. Reuses the in-progress local club if it hasn't been
    /// synced yet (so going back and forth in the setup doesn't spawn duplicates),
    /// otherwise starts a fresh club and makes it current.
    func createClub(name: String, tagline: String, logo: Data?, inviteCode: String? = nil) {
        if let cc, let idx = data.clubs.firstIndex(where: { $0.id == cc }),
           data.clubs[idx].remoteID == nil {
            data.clubs[idx].name = name
            data.clubs[idx].tagline = tagline
            if let logo { data.clubs[idx].logoData = logo }
            if let inviteCode { data.clubs[idx].inviteCode = inviteCode }
        } else {
            var club = Club()
            club.name = name
            club.tagline = tagline
            if let logo { club.logoData = logo }
            if let inviteCode { club.inviteCode = inviteCode }
            data.clubs.append(club)
            data.currentClubID = club.id
        }
    }

    /// Create an additional club from the profile (admin spins up a second Verein).
    /// The logged-in person becomes the admin member, the club is seeded with the
    /// default drink catalog and made the active club.
    @discardableResult
    func createAdditionalClub(name: String, tagline: String = "") -> Club {
        var club = Club()
        club.name = name
        club.tagline = tagline
        data.clubs.append(club)
        data.currentClubID = club.id

        if let email = data.identityEmail {
            let known = data.members.first { $0.email == email }
            var me = Member(name: known?.name ?? email, email: email, isAdmin: true,
                            emoji: known?.emoji ?? AvatarPool.random())
            me.clubID = club.id
            me.remoteID = known?.remoteID
            me.passwordHash = known?.passwordHash
            data.members.append(me)
            data.currentMemberID = me.id
        }
        var seed = DrinkCatalog.presets
        for i in seed.indices { seed[i].clubID = club.id }
        data.drinks.append(contentsOf: seed)
        return club
    }

    /// Generate a fresh invite code for the club (revokes the previous link).
    func regenerateInviteCode() {
        mutateCurrentClub { $0.inviteCode = Club.makeInviteCode() }
    }

    func setOpenInvite(_ on: Bool) {
        mutateCurrentClub { $0.openInvite = on }
    }

    /// Email address the "Getränke leer melden" reports are sent to.
    func setGetraenkewartEmail(_ email: String?) {
        let trimmed = email?.trimmingCharacters(in: .whitespacesAndNewlines)
        mutateCurrentClub { $0.getraenkewartEmail = (trimmed?.isEmpty == true) ? nil : trimmed }
    }

    /// Persist a new order of the drink tiles within the current club.
    func reorderDrinks(from source: IndexSet, to destination: Int) {
        var scoped = drinks
        scoped.move(fromOffsets: source, toOffset: destination)
        let others = data.drinks.filter { $0.clubID != cc }
        data.drinks = scoped + others
    }

    /// Shareable invite link for the club. Uses the https Universal-Link form so it
    /// also works for people who don't have the app yet (they land on the web page
    /// striche-app.de/join, which then hands off into the app or shows the App Store).
    var inviteLink: String {
        let code = club?.inviteCode ?? ""
        return "https://striche-app.de/join?code=\(code)"
    }

    /// Ready-to-send WhatsApp invite message including the link.
    var inviteMessage: String {
        let name = club?.name ?? "unserem Verein"
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
        guard let code = pendingInviteCode else { return false }
        // A captured invite code is valid if it matches ANY open-invite club we
        // already know about locally (cross-device join is validated server-side).
        return data.clubs.contains {
            $0.openInvite && code.caseInsensitiveCompare($0.inviteCode) == .orderedSame
        }
    }

    /// Replace the current club's drinks with a seed set (wizard).
    func setSeedDrinks(_ drinks: [Drink]) {
        var seeded = drinks
        for i in seeded.indices { seeded[i].clubID = cc }
        let others = data.drinks.filter { $0.clubID != cc }
        data.drinks = others + seeded
    }

    func addDrink(_ drink: Drink) {
        var d = drink
        d.clubID = cc
        data.drinks.append(d)
    }

    func updateDrink(_ drink: Drink) {
        if let idx = data.drinks.firstIndex(where: { $0.id == drink.id }) {
            data.drinks[idx] = drink
        }
    }

    func removeDrink(_ drink: Drink) { data.drinks.removeAll { $0.id == drink.id } }

    func updateClubLocation(lat: Double, lon: Double, radius: Double) {
        mutateCurrentClub {
            $0.latitude = lat
            $0.longitude = lon
            $0.geofenceRadius = radius
        }
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
        var link = WatchLink(bookerID: me.id, watcherID: watcher.id)
        link.clubID = cc
        data.watchLinks.append(link)
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
        if let existing = data.members.first(where: { $0.clubID == cc && $0.email == email }) {
            return existing
        }
        var m = Member(name: name.isEmpty ? email : name, email: email, isAdmin: isAdmin,
                       emoji: AvatarPool.random())
        m.clubID = cc
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
        // Whitelisted (pending) membership for this email in any club?
        if let idx = data.members.firstIndex(where: { $0.email == email }) {
            if data.members[idx].passwordHash != nil { return .alreadyRegistered }
            let pw = hash(password)
            // Same person may sit in several clubs – set the credential on all.
            for i in data.members.indices where data.members[i].email == email {
                data.members[i].passwordHash = pw
                if !name.isEmpty { data.members[i].name = name }
            }
            data.identityEmail = email
            data.currentClubID = data.members[idx].clubID
            data.currentMemberID = data.members[idx].id
            return .success
        }
        // Not whitelisted but a valid local invite link is present – join that club.
        if pendingInviteIsValid, let code = pendingInviteCode,
           let club = data.clubs.first(where: {
               $0.openInvite && code.caseInsensitiveCompare($0.inviteCode) == .orderedSame
           }) {
            var member = Member(name: name.isEmpty ? email : name, email: email,
                                emoji: AvatarPool.random())
            member.passwordHash = hash(password)
            member.clubID = club.id
            data.members.append(member)
            data.identityEmail = email
            data.currentClubID = club.id
            data.currentMemberID = member.id
            pendingInviteCode = nil
            return .success
        }
        // No club yet: establish an identity-only session so RootView shows the
        // "join a Verein" screen (NoClubView). The user can then enter an invite
        // code, or a server-side join (via the captured code) arrives on sync.
        data.identityEmail = email
        data.currentClubID = nil
        data.currentMemberID = nil
        return .success
    }

    func login(email: String, password: String) -> AuthResult {
        let email = email.lowercased()
        let mine = data.members.filter { $0.email == email }
        guard let first = mine.first else { return .notWhitelisted }
        guard let stored = first.passwordHash else { return .wrongPassword }
        guard stored == hash(password) else { return .wrongPassword }
        data.identityEmail = email
        // Keep the current club if the person still belongs to it, else pick the first.
        if let cc, mine.contains(where: { $0.clubID == cc }) {
            // keep current selection
        } else {
            data.currentClubID = first.clubID
        }
        data.currentMemberID = mine.first { $0.clubID == data.currentClubID }?.id
        return .success
    }

    func logout() {
        data.currentMemberID = nil
        data.currentClubID = nil
        data.identityEmail = nil
    }

    /// Adopt a backend-validated invite join on a fresh device (no local club yet).
    /// The invite code was already verified server-side by `/api/striche/join`, so we
    /// just establish the local session: match/create the member by backend user id,
    /// store the password hash for later offline login, and make them the current user.
    /// The club + roster + drinks then arrive via the subsequent pull.
    func adoptRemoteJoin(remoteUserID: String, email: String, password: String, name: String) {
        let email = email.lowercased()
        let pw = hash(password)
        for i in data.members.indices where data.members[i].email == email || data.members[i].remoteID == remoteUserID {
            data.members[i].remoteID = remoteUserID
            data.members[i].passwordHash = pw
            if !name.isEmpty { data.members[i].name = name }
        }
        if let m = data.members.first(where: { $0.remoteID == remoteUserID }) {
            data.currentClubID = m.clubID
            data.currentMemberID = m.id
        }
        // The joined club + roster + drinks arrive via the subsequent pull, which
        // sets a current club if none is selected yet.
        data.identityEmail = email
        pendingInviteCode = nil
    }

    /// Establish a local session for a backend user authenticated via OAuth (Google).
    /// Like `adoptRemoteJoin` but without a password hash (OAuth users have none –
    /// they re-authenticate via the stored token). Matches by backend id, then email.
    func adoptBackendUser(remoteUserID: String, email: String, name: String) {
        let email = email.lowercased()
        for i in data.members.indices where data.members[i].email == email || data.members[i].remoteID == remoteUserID {
            data.members[i].remoteID = remoteUserID
            if !name.isEmpty { data.members[i].name = name }
        }
        if let m = data.members.first(where: { $0.remoteID == remoteUserID }) {
            data.currentClubID = m.clubID
            data.currentMemberID = m.id
        }
        // No club yet -> RootView routes to the no-club screen until a pull or a
        // server-side join associates the user with a Verein.
        data.identityEmail = email
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

    /// Store the backend id on the current club (returned by the create/join hooks).
    func setClubRemoteID(_ remoteID: String) {
        mutateCurrentClub { if $0.remoteID != remoteID { $0.remoteID = remoteID } }
    }

    /// Store the backend id on a specific local club (used by multi-club push).
    func setClubRemoteID(_ localID: UUID, _ remoteID: String) {
        guard let idx = data.clubs.firstIndex(where: { $0.id == localID }),
              data.clubs[idx].remoteID != remoteID else { return }
        data.clubs[idx].remoteID = remoteID
    }

    /// The logged-in person's admin membership in a given club (for server-side
    /// club creation, which requires the authenticated caller to become admin).
    func adminMember(forClub clubID: UUID) -> Member? {
        guard let email = data.identityEmail else { return nil }
        return data.members.first { $0.clubID == clubID && $0.email == email && $0.isAdmin }
    }

    /// Members of a specific club (used by the multi-club sync).
    func members(ofClub clubID: UUID) -> [Member] {
        data.members.filter { $0.clubID == clubID }
    }

    func setMemberRemoteID(_ localID: UUID, _ remoteID: String) {
        if let i = data.members.firstIndex(where: { $0.id == localID }),
           data.members[i].remoteID != remoteID {
            data.members[i].remoteID = remoteID
        }
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

    /// Adopt/refresh a club from the backend (matched by remoteID). Returns the
    /// local club id so the pull can stamp its children. Keeps the local id + logo.
    /// Selects the club as current if none is selected yet (fresh-device join).
    @discardableResult
    func upsertPulledClub(_ remote: Club) -> UUID {
        if let i = data.clubs.firstIndex(where: { $0.remoteID != nil && $0.remoteID == remote.remoteID }) {
            data.clubs[i].name = remote.name
            data.clubs[i].tagline = remote.tagline
            data.clubs[i].inviteCode = remote.inviteCode
            data.clubs[i].openInvite = remote.openInvite
            data.clubs[i].latitude = remote.latitude
            data.clubs[i].longitude = remote.longitude
            data.clubs[i].geofenceRadius = remote.geofenceRadius
            data.clubs[i].planID = remote.planID
            data.clubs[i].pendingPlanID = remote.pendingPlanID
            data.clubs[i].getraenkewartEmail = remote.getraenkewartEmail
            if data.currentClubID == nil { data.currentClubID = data.clubs[i].id }
            return data.clubs[i].id
        }
        // Try to adopt a still-unsynced local club created offline by this admin
        // (keep its local id + logo, just attach the backend fields + remoteID).
        if let i = data.clubs.firstIndex(where: { $0.remoteID == nil && $0.name == remote.name }) {
            data.clubs[i].remoteID = remote.remoteID
            data.clubs[i].inviteCode = remote.inviteCode
            data.clubs[i].openInvite = remote.openInvite
            data.clubs[i].planID = remote.planID
            data.clubs[i].pendingPlanID = remote.pendingPlanID
            data.clubs[i].getraenkewartEmail = remote.getraenkewartEmail
            if data.currentClubID == nil { data.currentClubID = data.clubs[i].id }
            return data.clubs[i].id
        }
        data.clubs.append(remote)
        if data.currentClubID == nil { data.currentClubID = remote.id }
        return remote.id
    }

    func upsertPulledMember(_ remote: Member, clubID: UUID) {
        if let i = data.members.firstIndex(where: {
            $0.remoteID != nil && $0.remoteID == remote.remoteID && $0.clubID == clubID
        }) {
            data.members[i].name = remote.name
            data.members[i].email = remote.email
            data.members[i].emoji = remote.emoji
            data.members[i].isAdmin = remote.isAdmin
        } else {
            var m = remote; m.clubID = clubID
            data.members.append(m)
        }
    }

    /// Backend owns name/price/emoji/tint/sizes/icon; local keeps category/sound/symbol.
    func upsertPulledDrink(_ remote: Drink, clubID: UUID) {
        if let i = data.drinks.firstIndex(where: { $0.remoteID != nil && $0.remoteID == remote.remoteID }) {
            data.drinks[i].name = remote.name
            data.drinks[i].emoji = remote.emoji
            data.drinks[i].price = remote.price
            data.drinks[i].tintHex = remote.tintHex
            data.drinks[i].sizes = remote.sizes
            data.drinks[i].iconSymbol = remote.iconSymbol
            data.drinks[i].clubID = clubID
        } else {
            var d = remote; d.clubID = clubID
            data.drinks.append(d)
        }
    }

    func upsertPulledBooking(_ remote: Booking, clubID: UUID) {
        if let i = data.bookings.firstIndex(where: { $0.remoteID != nil && $0.remoteID == remote.remoteID }) {
            var b = remote; b.id = data.bookings[i].id; b.clubID = clubID
            data.bookings[i] = b
        } else {
            var b = remote; b.clubID = clubID
            data.bookings.insert(b, at: 0)
        }
    }

    func upsertPulledCreditTx(_ remote: CreditTransaction, clubID: UUID) {
        if let i = data.creditTx.firstIndex(where: { $0.remoteID != nil && $0.remoteID == remote.remoteID }) {
            var t = remote; t.id = data.creditTx[i].id; t.clubID = clubID
            data.creditTx[i] = t
        } else {
            var t = remote; t.clubID = clubID
            data.creditTx.append(t)
        }
    }

    func upsertPulledWatchLink(_ remote: WatchLink, clubID: UUID) {
        if let i = data.watchLinks.firstIndex(where: { $0.remoteID != nil && $0.remoteID == remote.remoteID }) {
            var w = remote; w.id = data.watchLinks[i].id; w.clubID = clubID
            data.watchLinks[i] = w
        } else {
            var w = remote; w.clubID = clubID
            data.watchLinks.append(w)
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
        var b = Booking(memberID: member.id,
                        drinkID: drink.id,
                        drinkName: drink.name,
                        sizeLabel: size?.label,
                        price: price)
        b.clubID = cc
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
        var tx = CreditTransaction(memberID: member.id, amount: amount,
                                   kind: .topUp,
                                   note: note ?? "Guthaben aufgeladen")
        tx.clubID = cc
        data.creditTx.append(tx)
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

    /// Total amount owed across all members of the current club.
    var grandTotal: Double {
        members.reduce(0) { $0 + total(for: $1) }
    }

    /// Total prepaid credit held across all members of the current club.
    var grandCredit: Double {
        members.reduce(0) { $0 + credit(for: $1) }
    }

    /// Settle the open tab in cash: clears the debt and marks bookings paid.
    func markPaid(member: Member) {
        let owed = total(for: member)
        if owed > 0 {
            var tx = CreditTransaction(memberID: member.id, amount: owed,
                                       kind: .settlement,
                                       note: "Deckel bar bezahlt")
            tx.clubID = cc
            data.creditTx.append(tx)
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
        let years = Set(bookings.map { cal.component(.year, from: $0.date) }
                        + clubCreditTx.map { cal.component(.year, from: $0.date) })
        return years.sorted(by: >)
    }

    /// Booked revenue per month (index 0 = Januar) for a given year.
    func monthlyRevenue(year: Int) -> [Double] {
        let cal = Calendar.current
        var months = Array(repeating: 0.0, count: 12)
        for b in bookings where cal.component(.year, from: b.date) == year {
            months[cal.component(.month, from: b.date) - 1] += b.price
        }
        return months
    }

    /// Money actually received per month (top-ups + settlements) for a given year.
    func monthlyPaid(year: Int) -> [Double] {
        let cal = Calendar.current
        var months = Array(repeating: 0.0, count: 12)
        for t in clubCreditTx where cal.component(.year, from: t.date) == year {
            months[cal.component(.month, from: t.date) - 1] += t.amount
        }
        return months
    }

    /// All bookings of the current club within a given month/year.
    func bookings(year: Int, month: Int) -> [Booking] {
        let cal = Calendar.current
        return bookings.filter {
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

    /// Number of seats currently in use (members in the current club).
    var usedSeats: Int { members.count }

    /// The plan the club is licensed for right now.
    var activePlan: SeatPlan { SeatPlans.plan(id: club?.planID ?? SeatPlan.freeID) }

    /// Smallest plan that would fit the current member count.
    var requiredPlan: SeatPlan { SeatPlans.required(forSeats: usedSeats) }

    /// Remaining free seats within the active plan (0 if overbooked).
    var seatsRemaining: Int { max(0, activePlan.maxSeats - usedSeats) }

    /// True when the club has more members than its active plan allows.
    var needsUpgrade: Bool { usedSeats > activePlan.maxSeats }

    /// A plan that was ordered but whose invoice is still open.
    var pendingPlan: SeatPlan? {
        guard let id = club?.pendingPlanID else { return nil }
        return SeatPlans.plan(id: id)
    }

    /// Order a plan. Paid plans are unlocked immediately (trust-based, invoice
    /// is sent manually); the pending flag marks the open invoice. Enterprise
    /// only records a contact request without changing the active plan.
    func requestPlan(_ plan: SeatPlan) {
        mutateCurrentClub {
            if plan.isEnterprise {
                $0.pendingPlanID = plan.id
            } else {
                $0.planID = plan.id
                $0.pendingPlanID = plan.isFree ? nil : plan.id
            }
        }
    }

    /// Marks the open invoice as settled (used later by the owner dashboard).
    func markPlanPaid() {
        mutateCurrentClub { $0.pendingPlanID = nil }
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

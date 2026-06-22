/// <reference path="../pb_data/types.d.ts" />

// Striche custom endpoints for the multi-tenant join flow.
//
// `memberships.createRule` is null in the schema (clients may NOT add themselves
// to a club directly), and `clubs` are only readable by their members. These two
// privileged routes run server-side, validate the request and create the
// membership with elevated DB access — the only sanctioned way to (a) bootstrap
// an admin for a freshly created club and (b) let a user join via an invite code.
//
// NOTE: PocketBase runs each routerAdd handler in an isolated goja VM, so file
// top-level functions are NOT visible inside a handler. Helpers must therefore be
// defined inside each handler (or loaded via require()).

// POST /api/striche/clubs -> create a club and make the caller its admin.
routerAdd("POST", "/api/striche/clubs", (e) => {
    const INVITE_CHARS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789" // no ambiguous chars
    function makeInviteCode() {
        let s = ""
        for (let i = 0; i < 6; i++) {
            s += INVITE_CHARS.charAt(Math.floor(Math.random() * INVITE_CHARS.length))
        }
        return s
    }
    function ensureMembership(app, userId, clubId, role) {
        let existing = null
        try {
            existing = app.findFirstRecordByFilter(
                "memberships",
                "user = {:user} && club = {:club}",
                { user: userId, club: clubId }
            )
        } catch (_) {
            existing = null
        }
        if (existing) return existing
        const col = app.findCollectionByNameOrId("memberships")
        const rec = new Record(col, { user: userId, club: clubId, role: role, invited: false })
        app.save(rec)
        return rec
    }

    const user = e.auth
    if (!user) throw new BadRequestError("Nicht angemeldet.")

    const body = e.requestInfo().body || {}
    const name = String(body.name || "").trim()
    if (!name) throw new BadRequestError("Vereinsname fehlt.")

    let code = String(body.invite_code || "").trim().toUpperCase()
    if (!code) code = makeInviteCode()

    const col = e.app.findCollectionByNameOrId("clubs")
    const club = new Record(col, {
        name: name,
        tagline: String(body.tagline || ""),
        invite_code: code,
        open_invite: body.open_invite === undefined ? true : !!body.open_invite,
        plan_id: String(body.plan_id || "free"),
        getraenkewart_email: String(body.getraenkewart_email || ""),
    })
    e.app.save(club)

    const membership = ensureMembership(e.app, user.id, club.id, "admin")
    return e.json(200, {
        club: club.id,
        membership: membership.id,
        invite_code: club.get("invite_code"),
    })
}, $apis.requireAuth())

// POST /api/striche/join -> join an existing club via its invite code.
routerAdd("POST", "/api/striche/join", (e) => {
    function ensureMembership(app, userId, clubId, role) {
        let existing = null
        try {
            existing = app.findFirstRecordByFilter(
                "memberships",
                "user = {:user} && club = {:club}",
                { user: userId, club: clubId }
            )
        } catch (_) {
            existing = null
        }
        if (existing) return existing
        const col = app.findCollectionByNameOrId("memberships")
        const rec = new Record(col, { user: userId, club: clubId, role: role, invited: false })
        app.save(rec)
        return rec
    }

    const user = e.auth
    if (!user) throw new BadRequestError("Nicht angemeldet.")

    const body = e.requestInfo().body || {}
    const code = String(body.invite_code || "").trim().toUpperCase()
    if (!code) throw new BadRequestError("Einladungscode fehlt.")

    let club = null
    try {
        club = e.app.findFirstRecordByFilter("clubs", "invite_code = {:code}", { code: code })
    } catch (_) {
        club = null
    }
    if (!club) throw new NotFoundError("Kein Verein mit diesem Code gefunden.")
    if (!club.getBool("open_invite")) throw new ForbiddenError("Dieser Verein nimmt aktuell keine neuen Mitglieder über Einladungslink auf.")

    const membership = ensureMembership(e.app, user.id, club.id, "member")
    return e.json(200, {
        club: club.id,
        membership: membership.id,
        invite_code: club.get("invite_code"),
    })
}, $apis.requireAuth())

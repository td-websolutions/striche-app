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

// POST /api/striche/invite-email -> e-mail a branded join invitation for a club.
// Only an admin of the given club may trigger this. Requires SMTP to be configured
// in the PocketBase settings, otherwise the send silently no-ops server-side.
routerAdd("POST", "/api/striche/invite-email", (e) => {
    const user = e.auth
    if (!user) throw new BadRequestError("Nicht angemeldet.")

    const body = e.requestInfo().body || {}
    const to = String(body.email || "").trim().toLowerCase()
    const clubId = String(body.club || "").trim()
    if (!to || to.indexOf("@") < 1) throw new BadRequestError("Ungültige E-Mail-Adresse.")
    if (!clubId) throw new BadRequestError("Verein fehlt.")

    // Authorise: caller must be an admin of this club.
    let membership = null
    try {
        membership = e.app.findFirstRecordByFilter(
            "memberships",
            "user = {:user} && club = {:club}",
            { user: user.id, club: clubId }
        )
    } catch (_) {
        membership = null
    }
    if (!membership || membership.get("role") !== "admin") {
        throw new ForbiddenError("Nur Admins dürfen Einladungen versenden.")
    }

    let club = null
    try {
        club = e.app.findRecordById("clubs", clubId)
    } catch (_) {
        club = null
    }
    if (!club) throw new NotFoundError("Verein nicht gefunden.")

    const clubName = String(club.get("name") || "Dein Verein")
    const code = String(club.get("invite_code") || "")
    const appUrl = "https://striche-app.de"
    const inviteLink = appUrl + "/join?code=" + encodeURIComponent(code)

    const html = ''
        + '<body style="margin:0;padding:0;background:#0B0D17;">'
        + '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#0B0D17;"><tr>'
        + '<td align="center" style="padding:32px 16px;">'
        + '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:520px;width:100%;background:#141831;border:1px solid rgba(255,255,255,0.10);border-radius:24px;overflow:hidden;font-family:\'Nunito\',\'Segoe UI\',Helvetica,Arial,sans-serif;">'
        + '<tr><td align="center" style="padding:36px 32px 8px;"><div style="font-size:52px;line-height:1;">🍻</div>'
        + '<div style="margin-top:10px;font-size:13px;font-weight:800;letter-spacing:0.18em;text-transform:uppercase;color:#F0B429;">Striche</div></td></tr>'
        + '<tr><td align="center" style="padding:12px 36px 4px;"><h1 style="margin:0;font-size:24px;font-weight:900;color:#FFFFFF;letter-spacing:-0.02em;">Du bist eingeladen!</h1>'
        + '<p style="margin:14px 0 0;font-size:15px;line-height:1.6;color:rgba(255,255,255,0.72);"><strong style="color:#FFFFFF;">' + clubName + '</strong> nutzt jetzt Striche – die digitale Strichliste fürs Vereinsheim. Tritt mit einem Tipp bei und buch deine Getränke ganz einfach per Fingertipp.</p></td></tr>'
        + '<tr><td align="center" style="padding:28px 36px 8px;"><a href="' + inviteLink + '" style="display:inline-block;padding:16px 34px;border-radius:16px;background:#F0B429;color:#2A1A00;font-size:16px;font-weight:800;text-decoration:none;">Verein beitreten</a></td></tr>'
        + '<tr><td align="center" style="padding:14px 36px 4px;"><p style="margin:0 0 8px;font-size:12px;line-height:1.6;color:rgba(255,255,255,0.50);">Oder gib in der App diesen Einladungscode ein:</p>'
        + '<div style="display:inline-block;padding:12px 22px;border-radius:14px;background:rgba(240,180,41,0.12);border:1px solid rgba(240,180,41,0.35);font-size:22px;font-weight:900;letter-spacing:0.22em;color:#F0B429;">' + code + '</div></td></tr>'
        + '<tr><td align="center" style="padding:14px 36px 0;"><p style="margin:0;font-size:12px;line-height:1.6;color:rgba(255,255,255,0.40);">Link geht nicht? Kopiere ihn in deinen Browser:<br/><a href="' + inviteLink + '" style="color:#F0B429;word-break:break-all;">' + inviteLink + '</a></p></td></tr>'
        + '<tr><td align="center" style="padding:28px 36px 32px;"><hr style="border:none;border-top:1px solid rgba(255,255,255,0.08);margin:0 0 16px;"/>'
        + '<p style="margin:0;font-size:12px;line-height:1.6;color:rgba(255,255,255,0.40);">Du kennst ' + clubName + ' nicht? Dann ignoriere diese E-Mail einfach.<br/><a href="' + appUrl + '" style="color:rgba(255,255,255,0.55);text-decoration:none;">' + appUrl + '</a></p></td></tr>'
        + '</table></td></tr></table></body>'

    const settings = e.app.settings()
    const message = new MailerMessage({
        from: {
            address: settings.meta.senderAddress,
            name: settings.meta.senderName,
        },
        to: [{ address: to }],
        subject: clubName + " lädt dich zu Striche ein 🍻",
        html: html,
    })
    e.app.newMailClient().send(message)

    return e.json(200, { sent: true })
}, $apis.requireAuth())

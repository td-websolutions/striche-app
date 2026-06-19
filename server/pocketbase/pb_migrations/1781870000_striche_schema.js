/// <reference path="../pb_data/types.d.ts" />

// Striche multi-tenant schema.
// Mandantenfähig: viele Vereine (clubs), sauber voneinander isoliert.
// Jede club-bezogene Collection trägt eine `club` Relation. Die Rules erlauben
// Zugriff nur Usern, die im selben Club eine Mitgliedschaft haben – geprüft über
// die Back-Relation auf der users-Seite (@request.auth.memberships_via_user).
// Dadurch sieht ein Verein NIE die Daten eines anderen Vereins.
//
// WICHTIG (PocketBase 0.39): Felder MÜSSEN als reine Objekte im `fields`-Array
// definiert werden. `new TextField()`-Instanzen im Array werden still verworfen.

migrate((app) => {
  const memberOfClub = '@request.auth.id != "" && @request.auth.memberships_via_user.club ?= club';

  // --- users (eingebaute auth-Collection) um Profilfelder erweitern ---
  const users = app.findCollectionByNameOrId("users");
  users.fields.add(new TextField({ name: "name", max: 100 }));
  users.fields.add(new TextField({ name: "emoji", max: 8 }));
  users.fields.add(new FileField({
    name: "avatar", maxSelect: 1, maxSize: 5242880,
    mimeTypes: ["image/png", "image/jpeg", "image/webp"],
  }));
  app.save(users);

  // --- clubs ---
  const clubs = new Collection({
    type: "base",
    name: "clubs",
    fields: [
      { name: "name", type: "text", required: true, max: 100 },
      { name: "tagline", type: "text", max: 140 },
      { name: "logo", type: "file", maxSelect: 1, maxSize: 5242880,
        mimeTypes: ["image/png", "image/jpeg", "image/webp"] },
      { name: "invite_code", type: "text", max: 16 },
      { name: "open_invite", type: "bool" },
      { name: "latitude", type: "number" },
      { name: "longitude", type: "number" },
      { name: "geofence_radius", type: "number" },
      { name: "plan_id", type: "text", max: 32 },
      { name: "pending_plan_id", type: "text", max: 32 },
      { name: "getraenkewart_email", type: "email" },
      { name: "created", type: "autodate", onCreate: true },
      { name: "updated", type: "autodate", onCreate: true, onUpdate: true },
    ],
    indexes: ["CREATE UNIQUE INDEX idx_clubs_invite_code ON clubs (invite_code)"],
  });
  app.save(clubs);

  // --- memberships (verbindet user <-> club mit Rolle) ---
  const memberships = new Collection({
    type: "base",
    name: "memberships",
    fields: [
      { name: "user", type: "relation", required: true, maxSelect: 1, collectionId: users.id, cascadeDelete: true },
      { name: "club", type: "relation", required: true, maxSelect: 1, collectionId: clubs.id, cascadeDelete: true },
      { name: "role", type: "select", required: true, maxSelect: 1, values: ["admin", "member"] },
      { name: "invited", type: "bool" },
      { name: "created", type: "autodate", onCreate: true },
      { name: "updated", type: "autodate", onCreate: true, onUpdate: true },
    ],
    indexes: ["CREATE UNIQUE INDEX idx_membership_user_club ON memberships (user, club)"],
  });
  // Rules, die die Back-Relation memberships_via_user nutzen, werden gesetzt,
  // nachdem die Collection (und damit die Back-Relation) existiert.
  memberships.createRule = null; // Beitritts-Logik kommt im Sync-Layer (Server/Hook)
  memberships.updateRule = null;
  memberships.deleteRule = null;
  app.save(memberships);

  const membershipsRules = app.findCollectionByNameOrId("memberships");
  membershipsRules.listRule = memberOfClub;
  membershipsRules.viewRule = memberOfClub;
  app.save(membershipsRules);

  // clubs-Rules (Back-Relation existiert jetzt)
  const clubsRules = app.findCollectionByNameOrId("clubs");
  clubsRules.listRule = '@request.auth.id != "" && @request.auth.memberships_via_user.club ?= id';
  clubsRules.viewRule = clubsRules.listRule;
  clubsRules.createRule = '@request.auth.id != ""';
  clubsRules.updateRule = clubsRules.listRule;
  clubsRules.deleteRule = null;
  app.save(clubsRules);

  // --- drinks (club-scoped) ---
  const drinks = new Collection({
    type: "base",
    name: "drinks",
    fields: [
      { name: "club", type: "relation", required: true, maxSelect: 1, collectionId: clubs.id, cascadeDelete: true },
      { name: "name", type: "text", required: true, max: 80 },
      { name: "emoji", type: "text", max: 8 },
      { name: "icon_symbol", type: "text", max: 60 },
      { name: "tint", type: "text", max: 16 },
      { name: "price", type: "number" },
      { name: "sizes", type: "json", maxSize: 20000 },
      { name: "sort_order", type: "number" },
      { name: "created", type: "autodate", onCreate: true },
      { name: "updated", type: "autodate", onCreate: true, onUpdate: true },
    ],
    listRule: memberOfClub,
    viewRule: memberOfClub,
    createRule: memberOfClub,
    updateRule: memberOfClub,
    deleteRule: memberOfClub,
  });
  app.save(drinks);

  // --- bookings (club-scoped) ---
  const bookings = new Collection({
    type: "base",
    name: "bookings",
    fields: [
      { name: "club", type: "relation", required: true, maxSelect: 1, collectionId: clubs.id, cascadeDelete: true },
      { name: "member", type: "relation", required: true, maxSelect: 1, collectionId: users.id, cascadeDelete: true },
      { name: "drink", type: "relation", maxSelect: 1, collectionId: drinks.id, cascadeDelete: false },
      { name: "drink_name", type: "text", max: 80 },
      { name: "size_label", type: "text", max: 40 },
      { name: "price", type: "number" },
      { name: "paid", type: "bool" },
      { name: "date", type: "date" },
      { name: "created", type: "autodate", onCreate: true },
      { name: "updated", type: "autodate", onCreate: true, onUpdate: true },
    ],
    indexes: ["CREATE INDEX idx_bookings_club_member ON bookings (club, member)"],
    listRule: memberOfClub,
    viewRule: memberOfClub,
    createRule: memberOfClub,
    updateRule: memberOfClub,
    deleteRule: memberOfClub,
  });
  app.save(bookings);

  // --- credit_transactions (Guthaben-Ledger, club-scoped) ---
  const creditTx = new Collection({
    type: "base",
    name: "credit_transactions",
    fields: [
      { name: "club", type: "relation", required: true, maxSelect: 1, collectionId: clubs.id, cascadeDelete: true },
      { name: "member", type: "relation", required: true, maxSelect: 1, collectionId: users.id, cascadeDelete: true },
      { name: "amount", type: "number" },
      { name: "kind", type: "select", required: true, maxSelect: 1, values: ["top_up", "settlement"] },
      { name: "note", type: "text", max: 200 },
      { name: "date", type: "date" },
      { name: "created", type: "autodate", onCreate: true },
      { name: "updated", type: "autodate", onCreate: true, onUpdate: true },
    ],
    indexes: ["CREATE INDEX idx_credit_club_member ON credit_transactions (club, member)"],
    listRule: memberOfClub,
    viewRule: memberOfClub,
    createRule: memberOfClub,
    updateRule: memberOfClub,
    deleteRule: memberOfClub,
  });
  app.save(creditTx);

  // --- watch_links (Benachrichtigungs-Consent, club-scoped) ---
  const watchLinks = new Collection({
    type: "base",
    name: "watch_links",
    fields: [
      { name: "club", type: "relation", required: true, maxSelect: 1, collectionId: clubs.id, cascadeDelete: true },
      { name: "booker", type: "relation", required: true, maxSelect: 1, collectionId: users.id, cascadeDelete: true },
      { name: "watcher", type: "relation", required: true, maxSelect: 1, collectionId: users.id, cascadeDelete: true },
      { name: "status", type: "select", required: true, maxSelect: 1, values: ["pending", "accepted", "declined"] },
      { name: "created", type: "autodate", onCreate: true },
      { name: "updated", type: "autodate", onCreate: true, onUpdate: true },
    ],
    indexes: ["CREATE UNIQUE INDEX idx_watch_unique ON watch_links (club, booker, watcher)"],
    listRule: memberOfClub,
    viewRule: memberOfClub,
    createRule: memberOfClub,
    updateRule: memberOfClub,
    deleteRule: memberOfClub,
  });
  app.save(watchLinks);
}, (app) => {
  for (const name of ["watch_links", "credit_transactions", "bookings", "drinks", "memberships", "clubs"]) {
    try { app.delete(app.findCollectionByNameOrId(name)); } catch (_) {}
  }
  const users = app.findCollectionByNameOrId("users");
  for (const f of ["name", "emoji", "avatar"]) {
    const field = users.fields.getByName(f);
    if (field) users.fields.removeById(field.id);
  }
  app.save(users);
});

# Striche – E-Mail-Versand einrichten

Die App schickt 4 Arten von E-Mails. Damit die wirklich rausgehen, braucht
PocketBase einen SMTP-Zugang. Es gibt **keinen** kostenlosen Versand ohne
SMTP-Login – aber es gibt kostenlose Standard-Anbieter. Empfohlen: **Brevo**
(~300 Mails/Tag gratis). Alternative: Resend (100/Tag).

Du musst die Schritte mit deinem eigenen Login machen – ich kann/darf keine
Konten anlegen oder Passwörter/API-Keys eingeben.

---

## 1. SMTP-Zugang besorgen (Brevo)

1. Konto anlegen auf https://www.brevo.com (gratis, "Free"-Plan).
2. Absender-Domain **striche-app.de** verifizieren:
   - Brevo → *Senders, Domains & Dedicated IPs* → *Domains* → *Add a domain*.
   - Brevo zeigt dir DNS-Einträge (DKIM `mail._domainkey…`, `dmarc`, ein
     `brevo-code` TXT). Trage die im DNS von striche-app.de ein.
   - Status muss auf **authenticated/verified** springen (kann etwas dauern).
3. SMTP-Zugangsdaten holen: Brevo → *SMTP & API* → *SMTP*. Du bekommst:
   - Host: `smtp-relay.brevo.com`
   - Port: `587`
   - Login: deine Brevo-Login-Mail
   - Passwort: der angezeigte **SMTP-Key** (nicht dein Brevo-Passwort!)

---

## 2. SMTP in PocketBase eintragen

PocketBase-Admin: `https://api.striche-app.de/_/` → *Settings* → *Mail settings*.

- **Sender name:** `Striche`
- **Sender address:** `noreply@striche-app.de` (muss zur verifizierten Domain passen)
- **Use SMTP mail server:** AN
- Host `smtp-relay.brevo.com`, Port `587`, Username = Brevo-Login,
  Password = SMTP-Key, TLS: `Auto (StartTLS)`.
- *Send test email* → an deine eigene Adresse. Muss ankommen.

> Die Absenderadresse (`senderAddress`/`senderName`) zieht auch der
> Einladungs-Hook automatisch – nichts doppelt eintragen.

---

## 3. Branded Templates einsetzen

Die fertigen HTML-Vorlagen liegen in `server/email-templates/`:

| Datei | PocketBase-Stelle (Collection `users` → *Options* → Mail-Templates) | Betreff |
|---|---|---|
| `verification.html`  | **Verification template**          | `Bestätige deine E-Mail für Striche 🍻` |
| `password-reset.html`| **Password reset template**        | `Setze dein Striche-Passwort zurück 🔑` |
| `email-change.html`  | **Confirm email change template**  | `Bestätige deine neue E-Mail-Adresse 📧` |

So einsetzen:
1. Admin → *Collections* → `users` → *Options* (Zahnrad) → Abschnitt
   *Mail templates*.
2. Jeweiligen Template-Body durch den **kompletten HTML-Inhalt** der Datei
   ersetzen, Betreff (Subject) wie in der Tabelle setzen.
3. Speichern. Platzhalter `{APP_NAME} {APP_URL} {ACTION_URL}` füllt PocketBase
   selbst.

> `App name` / `App url` stehen unter *Settings → Application*:
> App name `Striche`, App url `https://striche-app.de`. Diese landen in den
> `{APP_NAME}`/`{APP_URL}`-Platzhaltern.

Die 4. Vorlage `invite.html` ist **kein** PB-Template, sondern die
Vereins-Einladung, die der Server-Hook `POST /api/striche/invite-email`
verschickt (HTML ist im Hook `pb_hooks/striche.pb.js` inline – die Datei ist
nur die lesbare Referenz). Nichts einzustellen, läuft automatisch sobald SMTP
steht.

---

## 4. Hook deployen

Der Einladungs-Endpoint steckt in `server/pocketbase/pb_hooks/striche.pb.js`.
Auf den Server kopieren (PocketBase lädt Hooks per `--hooksWatch` automatisch
neu, kein Neustart nötig):

```bash
scp -i ~/.ssh/striche_contabo -o IdentitiesOnly=yes \
  server/pocketbase/pb_hooks/striche.pb.js \
  root@164.68.117.167:<PFAD-ZUM-pb_hooks-VOLUME>/striche.pb.js
```

(Pfad = das gemountete `pb_hooks`-Volume des PocketBase-Containers in Coolify.)

---

## Was die App damit auslöst

- **Registrierung:** App ruft nach `register()` automatisch
  `request-verification` → Bestätigungsmail (`verification.html`).
- **Passwort vergessen:** Login-Screen → *Passwort vergessen?* →
  `request-password-reset` → Reset-Mail (`password-reset.html`).
- **E-Mail ändern:** PocketBase-Standardfluss → `email-change.html`.
- **Mitglied einladen:** Admin lädt im Mitglieder-Screen jemanden per E-Mail
  ein → Hook `invite-email` schickt die Vereins-Einladung mit Beitritts-Link
  `https://striche-app.de/join?code=…`.

Ohne SMTP funktioniert die App normal weiter – die Mails werden dann serverseitig
nur still verworfen (kein Crash, kein Fehler in der App).

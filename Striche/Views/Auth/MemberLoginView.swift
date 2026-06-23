import SwiftUI

struct MemberLoginView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var backend: BackendSession
    @EnvironmentObject var sync: SyncEngine
    @Environment(\.dismiss) private var dismiss

    enum Mode { case login, register }
    @State private var mode: Mode = .login
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var showHint = false
    @State private var hintText = ""
    @State private var shake = false

    var body: some View {
        ZStack {
            AnimatedBackground()
            ScrollView {
                VStack(spacing: 24) {
                    header

                    if store.pendingInviteCode != nil {
                        inviteBanner
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    // Mode switcher
                    Picker("", selection: $mode) {
                        Text("Login").tag(Mode.login)
                        Text("Registrieren").tag(Mode.register)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 4)

                    VStack(spacing: 14) {
                        if mode == .register {
                            field(icon: "person.fill", placeholder: "Dein Name", text: $name)
                        }
                        field(icon: "envelope.fill", placeholder: "E-Mail-Adresse", text: $email,
                              keyboard: .emailAddress)
                        field(icon: "lock.fill", placeholder: "Passwort", text: $password, secure: true)
                    }
                    .padding(18)
                    .glassCard()
                    .offset(x: shake ? -10 : 0)

                    if showHint {
                        hintCard
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    Button(mode == .login ? "Einloggen" : "Konto erstellen") {
                        submit()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(email.isEmpty || password.count < 4)
                    .opacity(email.isEmpty || password.count < 4 ? 0.5 : 1)

                    if mode == .login {
                        Button("Passwort vergessen?") { forgotPassword() }
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.gold)
                            .padding(.top, 2)
                    }

                    orDivider
                    googleButton

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .navigationTitle("Mitglied")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .animation(.smooth, value: showHint)
        .animation(.smooth, value: mode)
        .onAppear { if store.pendingInviteCode != nil { mode = .register } }
    }

    private var orDivider: some View {
        HStack(spacing: 12) {
            Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)
            Text("oder")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
            Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)
        }
    }

    private var googleButton: some View {
        Button {
            loginWithGoogle()
        } label: {
            HStack(spacing: 12) {
                Text("G")
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(colors: [Color(hex: "#4285F4"), Color(hex: "#EA4335"),
                                                Color(hex: "#FBBC05"), Color(hex: "#34A853")],
                                       startPoint: .leading, endPoint: .trailing))
                Text("Mit Google fortfahren")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(hex: "#1F1F1F"))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black.opacity(0.08), lineWidth: 1))
        }
        .disabled(backend.isWorking)
        .opacity(backend.isWorking ? 0.6 : 1)
    }

    private var inviteBanner: some View {
        HStack(spacing: 12) {
            Text("🎉").font(.system(size: 24))
            VStack(alignment: .leading, spacing: 2) {
                Text(store.club != nil ? "Einladung zu \(store.club!.name)" : "Vereins-Einladung")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Registriere dich – du wirst automatisch verknüpft.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
            }
            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.gold.opacity(0.16), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.gold.opacity(0.5), lineWidth: 1))
    }

    private var header: some View {
        VStack(spacing: 10) {
            Text(mode == .login ? "👋" : "✍️").font(.system(size: 56))
            Text(mode == .login ? "Willkommen zurück" : "Neu dabei?")
                .font(.system(size: 24, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
            Text(mode == .login
                 ? "Logge dich ein und buche deine Getränke."
                 : "Registriere dich mit der E-Mail, die dein Verein hinterlegt hat.")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 12)
    }

    private var hintCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(Theme.gold)
                .font(.system(size: 20))
            Text(hintText)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.gold.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.gold.opacity(0.4), lineWidth: 1))
    }

    private func field(icon: String, placeholder: String, text: Binding<String>,
                       secure: Bool = false, keyboard: UIKeyboardType = .default) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(Theme.gold).frame(width: 22)
            Group {
                if secure {
                    SecureField(placeholder, text: text)
                } else {
                    TextField(placeholder, text: text)
                        .keyboardType(keyboard)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .font(.system(size: 16, weight: .medium, design: .rounded))
            .foregroundStyle(.white)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 14)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func submit() {
        let isRegister = (mode == .register)
        // Capture the invite code before local register() clears it.
        let joinCode = store.pendingInviteCode
        let result: AppStore.AuthResult = isRegister
            ? store.register(email: email, password: password, name: name)
            : store.login(email: email, password: password)

        switch result {
        case .success:
            Haptics.success()
            SoundManager.shared.play(.beer)
            syncBackendAuth(isRegister: isRegister, joinCode: joinCode)
        case .notWhitelisted:
            // Fresh-device join: no local club, but the user has an invite code.
            // Validate it against the live backend and pull the club down.
            if isRegister, let code = joinCode {
                attemptRemoteJoin(code: code)
            } else {
                fail("Diese E-Mail ist noch nicht freigeschaltet. Bitte gib deine E-Mail-Adresse an deinen Vereinsadministrator weiter, damit du Zugriff auf die Getränke zur Buchung erhältst. 🍺")
            }
        case .wrongPassword:
            fail("E-Mail oder Passwort stimmen nicht. Versuch es nochmal.")
        case .alreadyRegistered:
            fail("Für diese E-Mail gibt es schon ein Konto. Wechsle zum Login.")
        }
    }

    /// Mirror the local auth against the PocketBase backend (best-effort, offline-safe).
    /// Obtains a token + remote user id used for the later multi-device sync. Any
    /// failure is silent – the app keeps working locally.
    private func syncBackendAuth(isRegister: Bool, joinCode: String?) {
        let email = self.email
        let password = self.password
        let name = self.name.isEmpty ? (store.currentMember?.name ?? email) : self.name
        let emoji = store.currentMember?.emoji ?? ""
        Task {
            let ok = isRegister
                ? await backend.register(email: email, password: password, name: name, emoji: emoji)
                : await backend.login(email: email, password: password)
            guard ok, let uid = backend.userID else { return }
            store.setCurrentMemberRemoteID(uid)
            if let code = joinCode, let result = await backend.joinClub(inviteCode: code) {
                store.setClubRemoteID(result.club)
            }
            await sync.sync()
        }
    }

    /// Brand-new member on a device that has no local club: create/login the backend
    /// account, let the server validate the invite code and add the membership, then
    /// pull the club + roster + drinks. Only reached when local register() found no
    /// whitelisted email AND an invite code is present.
    private func attemptRemoteJoin(code: String) {
        let email = self.email
        let password = self.password
        let name = self.name.isEmpty ? email : self.name
        Task {
            // Create the backend account, or sign in if it already exists.
            var ok = await backend.register(email: email, password: password, name: name, emoji: "")
            if !ok { ok = await backend.login(email: email, password: password) }
            guard ok, let uid = backend.userID else {
                fail("Anmeldung am Server fehlgeschlagen. Prüfe deine Internetverbindung und versuch es erneut.")
                return
            }
            // Server-side validates the code, checks open_invite and creates the membership.
            guard await backend.joinClub(inviteCode: code) != nil else {
                fail("Dieser Einladungscode ist ungültig oder der Verein nimmt aktuell keine neuen Mitglieder auf.")
                return
            }
            // Establish the local session, then pull the club + roster + drinks.
            store.adoptRemoteJoin(remoteUserID: uid, email: email, password: password, name: name)
            await sync.sync()
            Haptics.success()
            SoundManager.shared.play(.beer)
        }
    }

    /// Sign in with Google. On success we establish the local session from the
    /// backend user record (no password), honour a pending invite code, and sync.
    private func loginWithGoogle() {
        let joinCode = store.pendingInviteCode
        Haptics.tap()
        Task {
            let ok = await backend.loginWithGoogle()
            guard ok, let uid = backend.userID, let user = backend.user else {
                if let err = backend.lastError { fail(err) }
                return
            }
            if let code = joinCode { _ = await backend.joinClub(inviteCode: code) }
            store.adoptBackendUser(remoteUserID: uid, email: user.email, name: user.name ?? "")
            await sync.sync()
            Haptics.success()
            SoundManager.shared.play(.beer)
        }
    }

    /// Trigger the password-reset e-mail. We always show the same confirmation
    /// (regardless of whether the address exists) so we don't leak who has a konto.
    private func forgotPassword() {
        guard email.contains("@") else {
            fail("Bitte gib oben zuerst deine E-Mail-Adresse ein, dann schicken wir dir einen Link zum Zurücksetzen.")
            return
        }
        let address = email
        Haptics.tap()
        Task {
            _ = await backend.requestPasswordReset(email: address)
            hintText = "Falls ein Konto mit \(address) existiert, haben wir dir gerade einen Link zum Zurücksetzen deines Passworts geschickt. Schau in dein Postfach. 📬"
            showHint = true
            Haptics.success()
        }
    }

    private func fail(_ msg: String) {
        Haptics.warning()
        hintText = msg
        showHint = true
        withAnimation(.spring(response: 0.2, dampingFraction: 0.2)) { shake = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.2)) { shake = false }
        }
    }
}

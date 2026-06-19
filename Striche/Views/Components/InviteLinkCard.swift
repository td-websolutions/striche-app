import SwiftUI

/// Shareable invite-link card: shows the link, copy + WhatsApp share buttons.
/// Anyone who opens the link and registers is auto-linked to the club.
struct InviteLinkCard: View {
    let link: String
    let message: String
    var onRegenerate: (() -> Void)? = nil

    @Environment(\.openURL) private var openURL
    @State private var copied = false

    private var whatsAppURL: URL? {
        let text = message.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "https://wa.me/?text=\(text)")
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "link.circle.fill")
                    .font(.system(size: 22)).foregroundStyle(Theme.gold)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Einladungslink").font(.system(size: 16, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    Text("Teile ihn in eurer WhatsApp-Gruppe – wer beitritt, wird automatisch verknüpft.")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }

            Text(link)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))

            HStack(spacing: 10) {
                Button {
                    UIPasteboard.general.string = link
                    Haptics.success()
                    withAnimation { copied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                        withAnimation { copied = false }
                    }
                } label: {
                    Label(copied ? "Kopiert!" : "Link kopieren",
                          systemImage: copied ? "checkmark.circle.fill" : "doc.on.doc.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle(filled: false))

                Button {
                    Haptics.tap()
                    if let url = whatsAppURL { openURL(url) }
                } label: {
                    Label("WhatsApp", systemImage: "paperplane.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
            }

            if let onRegenerate {
                Button {
                    Haptics.warning(); onRegenerate()
                } label: {
                    Label("Neuen Link erzeugen (alten ungültig machen)", systemImage: "arrow.triangle.2.circlepath")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .padding(18)
        .glassCard()
    }
}

import SwiftUI
import PhotosUI

struct AvatarEditSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var pickerItem: PhotosPickerItem?
    @State private var loading = false

    private var member: Member? { store.currentMember }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 5)

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.appBackground.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 22) {
                        preview

                        PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                            Label(loading ? "Lädt…" : "Eigenes Foto wählen", systemImage: "photo.on.rectangle.angled")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(loading)

                        if member?.avatarImage != nil {
                            Button {
                                Haptics.tap(); store.updateAvatar(emoji: member?.emoji ?? "🧑")
                            } label: {
                                Label("Foto entfernen", systemImage: "trash")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(PrimaryButtonStyle(filled: false))
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Oder Emoji wählen")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(Theme.gold)
                            LazyVGrid(columns: columns, spacing: 12) {
                                ForEach(AvatarPool.all, id: \.self) { e in
                                    emojiCell(e)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20).padding(.vertical, 16)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .navigationTitle("Profilbild")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } } }
            .toolbarColorScheme(.dark, for: .navigationBar)
            .onChange(of: pickerItem) { _, newItem in
                guard let newItem else { return }
                loading = true
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self),
                       let processed = AvatarImage.process(data) {
                        store.updateAvatar(photo: processed)
                        Haptics.success()
                    }
                    loading = false
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var preview: some View {
        Group {
            if let img = member?.avatarImage {
                Image(uiImage: img).resizable().scaledToFill()
                    .frame(width: 120, height: 120).clipShape(Circle())
                    .overlay(Circle().stroke(Theme.gold.opacity(0.5), lineWidth: 2))
            } else {
                Text(member?.emoji ?? "🧑")
                    .font(.system(size: 80))
                    .frame(width: 120, height: 120)
                    .background(Color.white.opacity(0.06), in: Circle())
            }
        }
    }

    private func emojiCell(_ e: String) -> some View {
        let isCurrent = member?.avatarData == nil && member?.emoji == e
        return Button {
            Haptics.selection(); store.updateAvatar(emoji: e)
        } label: {
            Text(e).font(.system(size: 30))
                .frame(width: 52, height: 52)
                .background(isCurrent ? Theme.gold.opacity(0.25) : Color.white.opacity(0.06), in: Circle())
                .overlay(Circle().stroke(isCurrent ? Theme.gold : Color.clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Downscale + compress picked photos before persisting in JSON

enum AvatarImage {
    static func process(_ data: Data, maxDimension: CGFloat = 400, quality: CGFloat = 0.8) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let size = image.size
        let scale = min(1, maxDimension / max(size.width, size.height))
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: quality)
    }
}

import SwiftUI

struct InAppNotificationBanner: View {
    @ObservedObject var center: InAppNotificationCenter
    var onSelect: ((InAppNotification) -> Void)?

    var body: some View {
        VStack(spacing: 8) {
            ForEach(center.active) { notification in
                bannerCard(notification)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: center.active)
    }

    private func bannerCard(_ notification: InAppNotification) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: notification.kind == .hint ? "lightbulb.fill" : "gift.fill")
                .foregroundStyle(notification.kind == .hint ? .yellow : .cyan)
                .font(.body)

            VStack(alignment: .leading, spacing: 2) {
                Text(notification.title)
                    .font(.subheadline.weight(.semibold))
                Text(notification.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            Spacer(minLength: 0)

            Button {
                center.dismiss(notification.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect?(notification)
            center.dismiss(notification.id)
        }
    }
}

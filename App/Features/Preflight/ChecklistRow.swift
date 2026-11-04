import SwiftUI

/// One line of the pre-flight checklist: symbol, title, current value and an optional action.
struct ChecklistRow: View {
    enum Status { case normal, attention }
    let symbol: String
    let title: String
    let value: String
    var status: Status = .normal
    var detail: String?
    var action: (() -> Void)?

    var body: some View {
        if let action {
            Button(action: action) { content(chevron: true) }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(title)
                .accessibilityValue([value, detail].compactMap { $0 }.joined(separator: ". "))
                .accessibilityAddTraits(.isButton)
        } else {
            content(chevron: false)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(title)
                .accessibilityValue([value, detail].compactMap { $0 }.joined(separator: ". "))
        }
    }

    private func content(chevron: Bool) -> some View {
        HStack(alignment: .top, spacing: Space.m) {
            Image(systemName: status == .attention ? "exclamationmark.triangle.fill" : symbol)
                .font(.title3).foregroundStyle(status == .attention ? Theme.warning : Theme.accent)
                .frame(width: 28).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.footnote.weight(.bold)).foregroundStyle(Theme.secondary)
                Text(value).font(.body).foregroundStyle(.primary).multilineTextAlignment(.leading)
                if let detail { Text(detail).font(.footnote).foregroundStyle(status == .attention ? Theme.warning : Theme.secondary).multilineTextAlignment(.leading) }
            }
            Spacer(minLength: Space.s)
            if chevron { Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondary).padding(.top, Space.xs).accessibilityHidden(true) }
        }
        .padding(.vertical, Space.s).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
    }
}

/// Rows grouped in one card, separated by hairlines.
struct ChecklistCard<Content: View>: View {
    var title: String?
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            if let title { Text(title).font(.headline).padding(.horizontal, Space.xs) }
            VStack(alignment: .leading, spacing: 0) { content() }
                .padding(.horizontal, Space.l).padding(.vertical, Space.xs)
                .frame(maxWidth: .infinity, alignment: .leading)
                .ftpCard(fill: 0.04)
        }
    }
}

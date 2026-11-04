import SwiftUI

/// A labelled menu picker. The native menu control always shows the selected value,
/// on Mac and iPhone, and fills its row with a 44-point target.
struct SelectionRow<Selection: Hashable, Content: View>: View {
    let title: String
    @Binding var selection: Selection
    @ViewBuilder let content: () -> Content

    init(_ title: String, selection: Binding<Selection>, @ViewBuilder content: @escaping () -> Content) {
        self.title = title; self._selection = selection; self.content = content
    }

    var body: some View {
        LabeledContent(title) {
            Picker(title, selection: $selection, content: content)
                .pickerStyle(.menu).labelsHidden()
        }
        .frame(minHeight: 44)
    }
}

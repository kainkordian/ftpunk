import SwiftUI
import FTPunkDomain

struct ActivityDetailView: View {
    @Bindable var model: AppModel
    let sessionID: UUID
    @State private var deleting = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        if let session = model.history.first(where: { $0.id == sessionID }) {
            RideSummaryView(model: model, session: session, history: true, done: { dismiss() }, delete: { deleting = true })
                .confirmationDialog("Delete this local activity?", isPresented: $deleting, titleVisibility: .visible) {
                    Button("Delete activity", role: .destructive) { model.delete(session); dismiss() }
                } message: { Text("The recording and pending upload are removed. Already uploaded activities and adopted FTP settings are kept.") }
        } else { ContentUnavailableView("Activity deleted", systemImage: "trash") }
    }
}

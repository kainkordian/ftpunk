import SwiftUI
import UniformTypeIdentifiers
import FTPunkDomain

struct ArchiveTransferView: View {
    @Bindable var model: AppModel
    @ViewState private var importing = false
    @ViewState private var reviewing = false
    @ViewState private var pending: PortableArchive? = nil
    @ViewState private var exportURL: URL? = nil
    @ViewState private var rollbackURL: URL? = nil
    @ViewState private var restored = false

    var body: some View {
        Section("Backup & transfer") {
            Text("Move riders, recordings, FTP history and workout library between FTPunk on Mac, iPhone and web. Saves remain independent until you transfer a file.")
                .font(.footnote).foregroundStyle(Theme.secondary)
            Button("Prepare portable backup") { exportURL = model.archiveFile() }
                .disabled(!model.canTransferData)
            if let exportURL { ShareLink("Save or share backup", item: exportURL) }
            Button("Import portable backup…") { importing = true }.disabled(!model.canTransferData)
            if restored { Label("Backup imported", systemImage: "checkmark.circle") }
            if let rollbackURL { ShareLink("Save the backup from before import", item: rollbackURL) }
            Text("Imports replace matching rider identities after review. Other riders stay unchanged. Accounts, credentials and upload approvals are never transferred.")
                .font(.footnote).foregroundStyle(Theme.secondary)
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= PortableArchive.maximumBytes else { throw ArchiveError.invalid("The archive exceeds 64 MB.") }
                pending = try PortableArchive.decode(Data(contentsOf: url))
                reviewing = true
            } catch { model.errorMessage = error.localizedDescription }
        }
        .alert("Import these riders?", isPresented: $reviewing) {
            Button("Import and replace matching riders", role: .destructive) {
                if let pending {
                    rollbackURL = model.restoreArchive(pending)
                    restored = rollbackURL != nil
                }
                pending = nil
            }
            Button("Cancel", role: .cancel) { pending = nil }
        } message: {
            if let pending {
                Text("\(pending.profiles.map(\.name).joined(separator: ", "))\n\(pending.activities.count) recordings, \(pending.workouts?.count ?? 0) cached workouts. Local history and workout library for these rider identities will be replaced, not merged. A local backup is saved first. Existing remote uploads are not deleted.")
            }
        }
    }
}

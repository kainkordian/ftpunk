import SwiftUI
import FTPunkDomain

/// Switch or add riders and edit weight and FTP. This is the only place the rider is chosen.
struct RiderSheet: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var newName = ""
    @State private var newFTP = ""
    private var fromIntervals: Bool { model.connection != nil && model.athleteSync.enabled }

    var body: some View {
        NavigationStack {
            Form {
                Section("Riders") {
                    ForEach(model.riders) { rider in
                        Button { model.selectRider(rider.id) } label: {
                            HStack(spacing: Space.m) {
                                Text(RiderInitials.make(rider.name)).font(.caption.weight(.bold)).frame(width: 32, height: 32)
                                    .background(Theme.accent.opacity(0.18), in: Circle()).accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(rider.name).foregroundStyle(.primary)
                                    Text(rider.currentFTP.map { "FTP \(Int($0.watts.rounded())) W" } ?? "No FTP yet")
                                        .font(.footnote).foregroundStyle(Theme.secondary)
                                }
                                Spacer(minLength: 0)
                                if rider.id == model.profile.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent).accessibilityLabel("Selected") }
                            }
                        }
                        .disabled(model.isBusy).accessibilityIdentifier("rider-\(rider.name)")
                    }
                    HStack {
                        TextField("New rider’s name", text: $newName)
                        Button("Add") { if model.addRider(name: newName) { newName = "" } }
                            .disabled(model.isBusy || newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                Section {
                    TextField("Name", text: $model.riderName)
                    LabeledContent("Weight, kg") { TextField("Optional", text: $model.weight).numberEntry().labelsHidden() }
                } header: { Text("Details") } footer: {
                    Text("Weight gives W/kg and picks the recommended ramp. Each rider keeps separate FTP and history."
                         + (fromIntervals ? " From Intervals.icu · edit to override." : ""))
                }
                Section {
                    LabeledContent("Current FTP", value: model.profile.currentFTP.map { "\(Int($0.watts.rounded())) W" } ?? "Not set")
                    if model.profile.ftpHistory.count > 1 || model.ftpSelection == "none" {
                        SelectionRow("FTP used", selection: $model.ftpSelection) {
                            if model.ftpSelection == "manual" { Text("Entered for this ride").tag("manual") }
                            Text("No FTP").tag("none")
                            ForEach(model.profile.ftpHistory) { entry in
                                Text("\(Int(entry.watts.rounded())) W · \(entry.date.formatted(date: .abbreviated, time: .omitted))").tag(entry.id.uuidString)
                            }
                        }
                    }
                    HStack {
                        TextField("New FTP, W", text: $newFTP).numberEntry().accessibilityLabel("New FTP in watts")
                        Button("Save") { if model.setCurrentFTP(newFTP) { newFTP = "" } }
                            .disabled(model.isBusy || newFTP.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } header: { Text("FTP") } footer: {
                    Text("Saving makes this the rider’s current FTP. Workouts and warm-ups use it. A test result is adopted from the result screen."
                         + (fromIntervals ? " From Intervals.icu · edit to override." : ""))
                }
            }
            .formStyle(.grouped).buttonStyle(FTPunkRowButtonStyle())
            .navigationTitle("Rider")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { if model.isBusy || model.saveRiderDetails() { dismiss() } } } }
        }
        #if os(macOS)
        .frame(minWidth: 380, idealWidth: 460, minHeight: 520)
        #endif
    }
}

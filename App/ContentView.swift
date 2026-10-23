import SwiftUI
import FTPunkDomain

struct ContentView: View {
    @Bindable var model: AppModel
    var body: some View {
        TabView(selection: $model.selectedTab) {
            SetupView(model: model).tabItem { Label("New test", systemImage: "plus.circle") }.tag(0)
            RideView(model: model).tabItem { Label("Ride", systemImage: "waveform.path.ecg") }.tag(1)
            HistoryView(model: model).tabItem { Label("Progress", systemImage: "chart.xyaxis.line") }.tag(2)
            SettingsView(model: model).tabItem { Label("Settings", systemImage: "gearshape") }.tag(3)
        }
        .tint(Theme.accent)
        .alert("FTPunk", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
        .sheet(item: $model.uploadConsent) { consent in UploadConsentView(model: model, consent: consent) }
    }
}

private struct UploadConsentView: View {
    @Bindable var model: AppModel
    let consent: UploadConsent
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("Test saved on this device", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.accent)
                    LabeledContent("Rider", value: consent.session.riderName)
                    LabeledContent("Test", value: consent.session.startedAt.formatted(date: .abbreviated, time: .shortened))
                }
                Section("Upload destination") {
                    LabeledContent("Intervals.icu account", value: consent.accountName)
                    Text("Account ID: \(consent.accountID)").font(.caption).foregroundStyle(.secondary)
                    Text("This sends the activity, including the rider’s name, to this account. Check the destination when sharing FTPunk with another rider.")
                        .font(.callout)
                }
                Button("Upload activity") {
                    model.uploadConsent = nil
                    Task { await model.confirmUpload(consent) }
                }.buttonStyle(.borderedProminent)
                Button("Keep local · not now") { model.uploadConsent = nil }
            }.formStyle(.grouped).navigationTitle("Upload this test?")
        }.frame(minWidth: 320, idealWidth: 500, minHeight: 420)
    }
}

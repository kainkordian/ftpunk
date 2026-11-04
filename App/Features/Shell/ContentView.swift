import SwiftUI
import FTPunkDomain
#if canImport(UIKit)
import UIKit
#endif

struct ContentView: View {
    @Bindable var model: AppModel
    var body: some View {
        Group {
            if model.onboardingPending {
                OnboardingView(model: model)
            } else if model.cockpitPresented, model.engine != nil {
                CockpitContainer(model: model)
            } else {
                AppShell(model: model)
            }
        }
        .tint(Theme.accent)
        .toggleStyle(FTPunkRowToggleStyle())
        .disclosureGroupStyle(FTPunkDisclosureStyle())
        .alert("FTPunk", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
        .alert("Use power matching?", isPresented: Binding(get: { model.powerMatchingPrompt != nil }, set: { if !$0 { model.powerMatchingPrompt = nil } })) {
            Button("Use power matching") { model.choosePowerMatching(true) }
            Button("Use meter for recording only") { model.choosePowerMatching(false) }
        } message: {
            Text("\(model.powerMatchingPrompt ?? "Your power meter") is connected. Power matching adjusts trainer resistance until this meter reads the workout target. Your choice is saved in Settings → Devices → Power source.")
        }
        .sheet(item: $model.uploadConsent) { consent in UploadConsentView(model: model, consent: consent) }
        .onChange(of: model.engine?.phase) { old, phase in
            #if canImport(UIKit)
            if let phase, UIAccessibility.isVoiceOverRunning {
                UIAccessibility.post(notification: .announcement, argument: phase.title)
            }
            #endif
            // A ride that ends while minimised (automatic finish, an interruption, Stop from the live-ride
            // bar) brings its result back on screen, so adoption and upload are never missed.
            if ResultPresentation.shouldPresent(previous: old, current: phase, cockpitPresented: model.cockpitPresented) { model.cockpitPresented = true }
        }
    }
}

private struct UploadConsentView: View {
    @Bindable var model: AppModel
    let consent: UploadConsent
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("Activity saved on this device", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.accent)
                    LabeledContent("Rider", value: consent.session.riderName)
                    LabeledContent("Activity", value: consent.session.startedAt.formatted(date: .abbreviated, time: .shortened))
                }
                Section("Upload destination") {
                    LabeledContent("Intervals.icu account", value: consent.accountName)
                    Text("Account ID: \(consent.accountID)").font(.caption).foregroundStyle(Theme.secondary)
                    Text("This sends the activity, including the rider’s name, to this account. Check the destination when sharing FTPunk with another rider.")
                        .font(.callout)
                }
                Button("Upload activity") {
                    model.uploadConsent = nil
                    Task { await model.confirmUpload(consent) }
                }.buttonStyle(FTPunkPrimaryButtonStyle())
                Button("Keep local · not now") { model.uploadConsent = nil }
            }.formStyle(.grouped).navigationTitle("Upload this activity?")
        }.frame(minWidth: 320, idealWidth: 500, minHeight: 420)
    }
}

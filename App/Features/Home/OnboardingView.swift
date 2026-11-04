import SwiftUI

/// First launch with no rider data: name, optional weight, and FTP if known.
struct OnboardingView: View {
    @Bindable var model: AppModel
    @State private var name = ""
    @State private var weight = ""
    @State private var ftp = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Welcome to FTPunk").font(.title2.bold())
                    Text("A few details make workouts fit you. Everything stays on this device.").foregroundStyle(Theme.secondary)
                }
                Section {
                    TextField("Your name", text: $name).accessibilityIdentifier("onboarding-name")
                    LabeledContent("Weight, kg") { TextField("Optional", text: $weight).numberEntry().labelsHidden() }
                    LabeledContent("FTP, watts") { TextField("If you know it", text: $ftp).numberEntry().labelsHidden() }
                } footer: {
                    Text("Weight gives W/kg and picks the recommended ramp. Not sure of your FTP? The FTP test will find it.")
                }
            }
            .formStyle(.grouped).buttonStyle(FTPunkRowButtonStyle())
            .navigationTitle("Set up")
            .safeAreaInset(edge: .bottom, spacing: 0) {
                PrimaryActionBar(title: "Continue", systemImage: "arrow.right",
                                 reason: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Enter your name to continue." : nil,
                                 isEnabled: !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                                 action: { model.completeOnboarding(name: name, weight: weight, ftp: ftp, thenTest: false) }) {
                    VStack(spacing: Space.s) {
                        Button("Not sure of my FTP: take the FTP test") { model.completeOnboarding(name: name, weight: weight, ftp: "", thenTest: true) }
                            .buttonStyle(FTPunkSecondaryButtonStyle()).controlSize(.large).frame(maxWidth: .infinity)
                            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .accessibilityIdentifier("onboarding-take-test")
                        Button("Skip for now") { model.skipOnboarding() }
                            .buttonStyle(FTPunkTertiaryButtonStyle()).accessibilityIdentifier("onboarding-skip")
                    }
                }
            }
        }
    }
}

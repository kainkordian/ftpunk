import SwiftUI
import FTPunkDomain

/// Full profile, steps and intensity label for any library workout. Start goes to the pre-flight.
struct WorkoutDetailSheet: View {
    @Bindable var model: AppModel
    let ref: WorkoutRef
    @Environment(\.dismiss) private var dismiss
    @State private var selectedStep: Int?
    @State private var zwoDocument: ActivityFileDocument?
    @State private var zwoName = ""
    @State private var exportingZWO = false

    var body: some View {
        NavigationStack {
            Group {
                if let detail = model.workoutDetail(for: ref) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: Space.l) {
                            VStack(alignment: .leading, spacing: Space.xs) {
                                Text(detail.title).font(.title2.bold())
                                Text([detail.category?.title, detail.source, DurationFormat.workout(detail.duration)].compactMap { $0 }.joined(separator: " · "))
                                    .font(.subheadline).foregroundStyle(Theme.secondary)
                                if let plan = detail.plan { Text(IntensityLabel.label(for: plan)).font(.headline) }
                                if let plan = detail.plan, let main = WorkoutPreview.mainSetText(for: plan) {
                                    Text("Main set: \(main)").font(.subheadline.monospacedDigit())
                                }
                            }
                            if let preview = detail.previewPlan {
                                WorkoutProfileChart(plan: preview, height: 160, selectedStep: $selectedStep, showsAxis: true, showsValues: !detail.needsFTP)
                                    .padding(.top, 28) // room for the tooltip above the chart
                            }
                            if detail.needsFTP {
                                Label("Needs FTP. Take an FTP test or set your FTP to see targets in watts.", systemImage: "info.circle")
                                    .font(.callout).foregroundStyle(Theme.warning)
                            } else if let plan = detail.plan {
                                ftpNote(detail, plan)
                            }
                            if let list = detail.plan ?? detail.previewPlan { stepList(list, showValues: !detail.needsFTP) }
                        }
                        .padding(Space.l).frame(maxWidth: 700).frame(maxWidth: .infinity)
                    }
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        PrimaryActionBar(title: "Start", systemImage: "play.fill", reason: detail.needsFTP ? StartBlocker.needsFTP.reason : nil,
                                         isEnabled: !detail.needsFTP && !model.isBusy) {
                            dismiss(); model.openPreflight(.workout(ref))
                        }
                    }
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            Menu {
                                if let custom = detail.custom { Button("Edit") { dismiss(); model.editWorkout(custom) } }
                                if model.duplicate(ref) != nil { Button("Duplicate & edit") { dismiss(); model.duplicateAndEdit(ref) } }
                                if let plan = detail.plan { Button("Export as ZWO") { exportZWO(plan) } }
                                if let cached = detail.cached { Button("Remove from library", role: .destructive) { model.deleteWorkout(cached); dismiss() } }
                                if let custom = detail.custom { Button("Delete workout", role: .destructive) { model.deleteCustomWorkout(custom); dismiss() } }
                            } label: { Image(systemName: "ellipsis.circle") }
                                .disabled(model.isBusy).accessibilityLabel("Workout options")
                        }
                    }
                    .fileExporter(isPresented: $exportingZWO, document: zwoDocument, contentType: .zwo, defaultFilename: zwoName) { result in
                        if case .failure(let error) = result { model.errorMessage = error.localizedDescription }
                    }
                } else {
                    ContentUnavailableView("Workout removed", systemImage: "trash")
                }
            }
            .navigationTitle("Workout").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
        #if os(macOS)
        .frame(minWidth: 420, idealWidth: 520, minHeight: 560)
        #endif
    }

    private func exportZWO(_ plan: TrainingPlan) {
        do {
            zwoDocument = ActivityFileDocument(data: try ZWOExport.data(plan, ftp: model.libraryFTP))
            zwoName = (ZWOExport.fileName(for: plan) as NSString).deletingPathExtension
            exportingZWO = true
        } catch { model.errorMessage = error.localizedDescription }
    }

    private func ftpNote(_ detail: AppModel.WorkoutDetail, _ plan: TrainingPlan) -> some View {
        let current = model.libraryFTP
        let used = plan.ftpWatts
        let differs = detail.cached != nil && used != nil && current != nil && abs((used ?? 0) - (current ?? 0)) > 0.5
        return VStack(alignment: .leading, spacing: 2) {
            if let used { Text(detail.cached == nil ? "Targets use your FTP of \(Int(used.rounded())) W." : "Targets are fixed in watts (saved at \(Int(used.rounded())) W FTP).").font(.callout) }
            else { Text("Targets are fixed in watts.").font(.callout) }
            if differs, let current { Text("Your current FTP is \(Int(current.rounded())) W. This workout does not rescale.").font(.footnote).foregroundStyle(Theme.warning) }
        }
    }

    /// Name, then duration, % FTP and watts in fixed-width columns. Hovering or tapping a row highlights its bar.
    private func stepList(_ plan: TrainingPlan, showValues: Bool) -> some View {
        let steps = WorkoutPreview.steps(for: plan, showValues: showValues)
        return Grid(alignment: .trailing, horizontalSpacing: Space.m, verticalSpacing: 0) {
            ForEach(steps, id: \.index) { step in
                GridRow {
                    HStack(spacing: Space.s) {
                        RoundedRectangle(cornerRadius: 3).fill(step.zone.map(ZonePalette.color(for:)) ?? Theme.secondary.opacity(0.5))
                            .frame(width: 12, height: 12).accessibilityHidden(true)
                        Text(step.name).font(.subheadline)
                    }.gridColumnAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                    Text(step.durationText).frame(minWidth: 44, alignment: .trailing)
                    if showValues {
                        Text(step.percentText ?? "").frame(minWidth: 64, alignment: .trailing)
                        Text(step.wattsText).frame(minWidth: 72, alignment: .trailing)
                    }
                }
                .font(.subheadline).monospacedDigit()
                .padding(.vertical, Space.s).frame(minHeight: 36)
                .background(selectedStep == step.index ? Theme.accent.opacity(0.12) : Color.clear)
                .contentShape(Rectangle())
                .onHover { selectedStep = $0 ? step.index : (selectedStep == step.index ? nil : selectedStep) }
                .onTapGesture { selectedStep = selectedStep == step.index ? nil : step.index }
                .accessibilityElement(children: .ignore).accessibilityLabel(step.spokenText)
                Divider().gridCellColumns(showValues ? 4 : 2)
            }
        }
    }
}

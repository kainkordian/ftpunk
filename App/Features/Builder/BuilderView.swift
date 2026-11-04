import SwiftUI
import FTPunkDomain

/// The workout builder: one screen with two editors, Blocks and Text, and a profile chart that follows whichever is open.
/// Wide windows put the editor and the chart side by side; a phone stacks the chart over the editor.
struct BuilderView: View {
    @Bindable var model: AppModel
    let request: BuilderRequest
    @State private var state: BuilderState
    @State private var selected: Int?
    @State private var confirmDiscard = false
    @State private var showChart = true
    @State private var width = 0.0
    @AppStorage("builderMode") private var storedMode = BuilderState.Mode.blocks.rawValue
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(model: AppModel, request: BuilderRequest) {
        self.model = model; self.request = request
        _state = State(initialValue: request.state)
    }

    private var ftp: Double? { model.libraryFTP }
    private var wide: Bool { width >= CockpitLayout.sideBySideMinimumWidth }
    private var modeBinding: Binding<BuilderState.Mode> {
        Binding(get: { state.mode }, set: { mode in
            if state.switchTo(mode) { storedMode = mode.rawValue }
        })
    }

    var body: some View {
        NavigationStack {
            Group {
                if wide {
                    HStack(alignment: .top, spacing: Space.l) {
                        editor.frame(maxWidth: .infinity)
                        ScrollView { preview.padding(Space.l) }.frame(maxWidth: 460)
                    }
                } else {
                    VStack(spacing: 0) {
                        if showChart && !dynamicTypeSize.isAccessibilitySize { preview.padding([.horizontal, .top], Space.l).padding(.bottom, Space.s) }
                        editor
                    }
                }
            }
            .navigationTitle(request.isNew ? "New workout" : "Edit workout")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { if state.hasUnsavedChanges { confirmDiscard = true } else { dismiss() } }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { if model.saveCustomWorkout(state.workout(riderID: request.state.workout().riderID)) { dismiss() } }
                        .disabled(!state.canSave).accessibilityIdentifier("builder-save")
                }
            }
            .confirmationDialog("Discard your changes?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Discard changes", role: .destructive) { dismiss() }
                Button("Keep editing", role: .cancel) {}
            }
        }
        .modifier(ReadWidth(width: $width))
        .interactiveDismissDisabled(state.hasUnsavedChanges)
        .onAppear {
            if request.mode == nil, storedMode == BuilderState.Mode.text.rawValue { state.switchTo(.text) }
        }
        #if os(macOS)
        .frame(minWidth: 560, idealWidth: 920, minHeight: 620)
        #endif
    }

    // MARK: Chart and summary

    private var plan: TrainingPlan? {
        guard state.shownBlocks.isEmpty == false else { return nil }
        let draft = CustomWorkout(riderID: request.state.workout().riderID, name: state.name.isEmpty ? "Workout" : state.name, blocks: state.shownBlocks)
        return try? draft.plan(ftp: ftp ?? 100)
    }

    @ViewBuilder private var preview: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            if let plan {
                WorkoutProfileChart(plan: plan, height: wide ? 180 : 96, selectedStep: $selected, showsAxis: ftp != nil, showsValues: ftp != nil)
                    .opacity(state.chartIsStale ? 0.35 : 1)
                    .accessibilityLabel(state.chartIsStale ? "Workout profile, from the last text that was valid" : "Workout profile")
                if state.chartIsStale { Label("Showing the last valid text", systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(Theme.warning) }
                summary(plan)
            } else {
                RoundedRectangle(cornerRadius: 8).fill(Theme.secondary.opacity(0.12)).frame(height: wide ? 180 : 96)
                    .overlay { Text("Add a step to see the profile").font(.footnote).foregroundStyle(Theme.secondary) }
            }
        }
    }

    private func summary(_ plan: TrainingPlan) -> some View {
        let draft = CustomWorkout(riderID: request.state.workout().riderID, name: "Workout", blocks: state.shownBlocks)
        return VStack(alignment: .leading, spacing: 2) {
            Text(DurationFormat.workout(plan.duration)).font(.headline)
            if let main = WorkoutPreview.mainSetText(for: plan, showValues: ftp != nil || !draft.needsFTP) { Text("Main set: \(main)").font(.subheadline.monospacedDigit()) }
            if let load = draft.estimatedLoad(ftp: ftp) {
                Text(String(format: "IF %.2f · TSS %.0f (estimated)", load.intensityFactor, load.tss)).font(.subheadline.monospacedDigit()).foregroundStyle(Theme.secondary)
            } else if ftp == nil {
                Text("Set an FTP to see IF and TSS.").font(.footnote).foregroundStyle(Theme.secondary)
            }
        }
    }

    // MARK: Editor

    @ViewBuilder private var editor: some View {
        if state.mode == .blocks { blocksEditor } else { textEditor }
    }

    @ViewBuilder private var header: some View {
        TextField("Workout name", text: $state.name).accessibilityIdentifier("builder-name")
        Picker("Category", selection: $state.category) {
            Text("No category").tag(WorkoutCategory?.none)
            ForEach(WorkoutCategory.allCases) { Text($0.title).tag(WorkoutCategory?.some($0)) }
        }
        Picker("Editor", selection: modeBinding) {
            Text("Blocks").tag(BuilderState.Mode.blocks); Text("Text").tag(BuilderState.Mode.text)
        }.pickerStyle(.segmented).accessibilityIdentifier("builder-mode")
        if let notice = state.notice { Label(notice, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(Theme.warning) }
    }

    @ViewBuilder private var blockers: some View {
        let reasons = state.mode == .blocks ? state.saveBlockers : []
        if !reasons.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(reasons, id: \.self) { Text($0).font(.footnote).foregroundStyle(Theme.warning) }
            }.accessibilityElement(children: .combine)
        }
    }

    /// Name, category and the mode switch: the same block above the steps in Blocks mode and above the text in Text mode,
    /// so switching modes does not move anything.
    private var headerArea: some View {
        VStack(alignment: .leading, spacing: Space.s) { header }.padding([.horizontal, .top], Space.l).padding(.bottom, Space.s)
    }

    private var blocksEditor: some View {
        let ranges = state.workout().flatRanges()
        return VStack(alignment: .leading, spacing: 0) {
            headerArea
            List {
            Section {
                ForEach(Array(state.blocks.enumerated()), id: \.offset) { index, block in
                    BlockRow(block: binding(index), ftp: ftp, highlighted: selected.map { ranges.indices.contains(index) && ranges[index].contains($0) } ?? false,
                             onSelect: { selected = ranges.indices.contains(index) ? ranges[index].lowerBound : nil },
                             duplicate: { duplicate(index) }, delete: { delete(index) },
                             moveUp: index > 0 ? { move(index, by: -1) } : nil, moveDown: index < state.blocks.count - 1 ? { move(index, by: 1) } : nil)
                }
                .onMove { source, destination in
                    var blocks = state.blocks; blocks.move(fromOffsets: source, toOffset: destination); state.setBlocks(blocks)
                }
                .onDelete { offsets in var blocks = state.blocks; blocks.remove(atOffsets: offsets); state.setBlocks(blocks) }
                addMenu
            } header: { Text("Steps") } footer: { blockers }
            }
            .formStyle(.grouped).buttonStyle(FTPunkRowButtonStyle())
            .accessibilityIdentifier("builder-blocks")
        }
    }

    private func binding(_ index: Int) -> Binding<CustomWorkout.Block> {
        Binding(get: { state.blocks.indices.contains(index) ? state.blocks[index] : .step(.init(seconds: 60, start: .percentFTP(0.5))) },
                set: { value in var blocks = state.blocks; if blocks.indices.contains(index) { blocks[index] = value; state.setBlocks(blocks) } })
    }
    private func duplicate(_ index: Int) { var blocks = state.blocks; blocks.insert(blocks[index], at: index + 1); state.setBlocks(blocks) }
    private func delete(_ index: Int) { var blocks = state.blocks; blocks.remove(at: index); state.setBlocks(blocks) }
    private func move(_ index: Int, by delta: Int) {
        var blocks = state.blocks; blocks.swapAt(index, index + delta); state.setBlocks(blocks)
    }
    private func append(_ block: CustomWorkout.Block) { state.setBlocks(state.blocks + [block]) }

    private var addMenu: some View {
        Menu {
            Button("Step") { append(.step(.init(seconds: 300, start: .percentFTP(0.75)))) }
            Button("Repeat block") { append(.repeats(count: 4, steps: [.init(name: "Hard", seconds: 180, start: .percentFTP(1.1)), .init(name: "Easy", seconds: 120, start: .percentFTP(0.5))])) }
            Divider()
            Button("Warm-up 10 min @ 50 %") { append(.step(.init(name: "Warm-up", seconds: 600, start: .percentFTP(0.5)))) }
            Button("Cool-down 5 min @ 50 %") { append(.step(.init(name: "Cool-down", seconds: 300, start: .percentFTP(0.5)))) }
            Button("Recovery 2 min @ 50 %") { append(.step(.init(name: "Recovery", seconds: 120, start: .percentFTP(0.5)))) }
        } label: { Label("Add step or repeat", systemImage: "plus.circle") }
            .accessibilityIdentifier("builder-add")
    }

    private var textEditor: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            headerArea
            TextEditor(text: Binding(get: { state.text }, set: { state.setText($0) }))
                .font(.system(.body, design: .monospaced))
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .scrollContentBackground(.hidden)
                .padding(Space.s).background(Theme.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, Space.l).frame(minHeight: 160)
                .accessibilityLabel("Workout text").accessibilityIdentifier("builder-text")
            VStack(alignment: .leading, spacing: 2) {
                if state.parsed.isValid {
                    Label("Text is valid", systemImage: "checkmark.circle").font(.footnote).foregroundStyle(Theme.accent)
                } else {
                    ForEach(Array(state.parsed.errors.enumerated()), id: \.offset) { _, error in
                        Text("Line \(error.line): \(error.message)").font(.footnote).foregroundStyle(Theme.warning)
                    }
                }
                Text("Steps start with “-”: duration (10m, 30s, 1m30), then 80 % or 200w or ramp 60-80%. A line ending in 5x repeats the steps under it. Text before the duration names the step.")
                    .font(.footnote).foregroundStyle(Theme.secondary)
                if let issue = state.parsed.isValid ? state.workout().issues().first : nil {
                    Text(issue).font(.footnote).foregroundStyle(Theme.warning)
                }
            }.padding(.horizontal, Space.l).accessibilityElement(children: .combine)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Rows

private struct BlockRow: View {
    @Binding var block: CustomWorkout.Block
    let ftp: Double?
    let highlighted: Bool
    let onSelect: () -> Void
    let duplicate: () -> Void
    let delete: () -> Void
    let moveUp: (() -> Void)?
    let moveDown: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            switch block {
            case .step:
                StepEditor(step: stepBinding, ftp: ftp)
            case .repeats(let count, let steps):
                HStack {
                    Stepper(value: Binding(get: { count }, set: { block = .repeats(count: $0, steps: steps) }), in: CustomWorkout.repeatRange) {
                        Text("Repeat × \(count)").font(.headline)
                    }
                }
                ForEach(Array(steps.enumerated()), id: \.offset) { index, _ in
                    StepEditor(step: Binding(get: { steps.indices.contains(index) ? steps[index] : steps[0] },
                                             set: { var copy = steps; copy[index] = $0; block = .repeats(count: count, steps: copy) }), ftp: ftp)
                        .padding(.leading, Space.m)
                        .contextMenu {
                            Button("Duplicate step") { var copy = steps; copy.insert(steps[index], at: index + 1); block = .repeats(count: count, steps: copy) }
                            Button("Delete step", role: .destructive) { var copy = steps; copy.remove(at: index); block = .repeats(count: count, steps: copy) }
                                .disabled(steps.count <= 1)
                        }
                }
                Button { block = .repeats(count: count, steps: steps + [.init(seconds: 60, start: .percentFTP(0.5))]) } label: { Label("Add step to repeat", systemImage: "plus") }
                    .font(.subheadline)
            }
            HStack {
                Button("Duplicate", action: duplicate)
                Button("Delete", role: .destructive, action: delete)
                if let moveUp { Button { moveUp() } label: { Image(systemName: "arrow.up") }.accessibilityLabel("Move up") }
                if let moveDown { Button { moveDown() } label: { Image(systemName: "arrow.down") }.accessibilityLabel("Move down") }
            }.font(.footnote).buttonStyle(.borderless)
        }
        .padding(.vertical, Space.xs)
        .background(highlighted ? Theme.accent.opacity(0.1) : Color.clear)
        .contentShape(Rectangle()).onTapGesture(perform: onSelect)
    }

    private var stepBinding: Binding<CustomWorkout.Step> {
        Binding(get: { if case .step(let step) = block { step } else { .init(seconds: 60, start: .percentFTP(0.5)) } },
                set: { block = .step($0) })
    }
}

/// One step: name, duration, target (unit, value, optional ramp end) and what that means at the rider's FTP.
private struct StepEditor: View {
    @Binding var step: CustomWorkout.Step
    let ftp: Double?
    @State private var durationText = ""
    @State private var durationInvalid = false

    private var isPercent: Bool { step.start.isPercent }
    private var isRamp: Bool { step.end != nil }
    private var zoneColor: Color {
        let fraction: Double? = isPercent ? step.start.number : ftp.map { step.start.number / $0 }
        return fraction.map { ZonePalette.color(for: IntensityZone.zone(forFraction: $0)) } ?? Theme.secondary.opacity(0.5)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(spacing: Space.s) {
                RoundedRectangle(cornerRadius: 3).fill(zoneColor).frame(width: 12, height: 24).accessibilityHidden(true)
                TextField("Name (optional)", text: $step.name).accessibilityLabel("Step name")
            }
            if !CustomWorkout.nameIsPlain(step.name) {
                Text("The name cannot contain line breaks, '@', or words such as 10m, 80%, 200w, ramp or 5x.").font(.footnote).foregroundStyle(Theme.warning)
            }
            HStack {
                TextField("m:ss", text: $durationText)
                    .frame(maxWidth: 90).multilineTextAlignment(.trailing).monospacedDigit()
                    .onSubmit(commitDuration)
                    .accessibilityLabel("Duration")
                    .foregroundStyle(durationInvalid ? Theme.warning : Color.primary)
                Stepper("Duration", value: Binding(get: { step.seconds }, set: { step.seconds = min(14400, max(5, $0)); durationText = CustomWorkout.durationText(step.seconds); durationInvalid = false }),
                        in: 5...14400, step: 15).labelsHidden()
            }
            Picker("Unit", selection: Binding(get: { isPercent }, set: setUnit)) {
                Text("% FTP").tag(true); Text("W").tag(false)
            }.pickerStyle(.segmented).accessibilityLabel("Target unit")
            targetRow(title: isRamp ? "From" : "Target", value: Binding(get: { step.start }, set: { step.start = $0 }))
            Toggle("Ramp", isOn: Binding(get: { isRamp }, set: { on in step.end = on ? step.start : nil }))
            if let end = step.end { targetRow(title: "To", value: Binding(get: { end }, set: { step.end = $0 })) }
            Text(equivalent).font(.footnote).foregroundStyle(Theme.secondary)
        }
        .onAppear { durationText = CustomWorkout.durationText(step.seconds) }
    }

    private func commitDuration() {
        if let seconds = CustomWorkout.parseDuration(durationText), CustomWorkout.stepSeconds.contains(seconds) {
            step.seconds = seconds; durationInvalid = false
        } else { durationInvalid = true }
        if !durationInvalid { durationText = CustomWorkout.durationText(step.seconds) }
    }

    private func setUnit(_ percent: Bool) {
        guard percent != isPercent else { return }
        func convert(_ target: CustomWorkout.Target) -> CustomWorkout.Target {
            if percent { return .percentFTP(ftp.map { min(2.5, max(0.3, target.number / $0)) } ?? 0.75) }
            return .watts(ftp.map { min(1500, max(20, (target.number * $0).rounded())) } ?? 150)
        }
        step.start = convert(step.start); step.end = step.end.map(convert)
    }

    private func targetRow(title: String, value: Binding<CustomWorkout.Target>) -> some View {
        let shown = Binding<Double>(
            get: { isPercent ? (value.wrappedValue.number * 100).rounded() : value.wrappedValue.number.rounded() },
            set: { number in value.wrappedValue = isPercent ? .percentFTP(number / 100) : .watts(number) })
        return HStack {
            Text(title).frame(width: 64, alignment: .leading)
            TextField(isPercent ? "% FTP" : "Watts", value: shown, format: .number.precision(.fractionLength(0)))
                .multilineTextAlignment(.trailing).monospacedDigit().frame(maxWidth: 80).accessibilityLabel("\(title) \(isPercent ? "percent of FTP" : "watts")")
            Text(isPercent ? "%" : "W").foregroundStyle(Theme.secondary)
            Stepper(title, value: shown, in: isPercent ? 30...250 : 20...1500, step: 5).labelsHidden()
        }
    }

    private var equivalent: String {
        func text(_ target: CustomWorkout.Target) -> String {
            if isPercent { return ftp.map { "\(Int((target.number * $0).rounded())) W" } ?? "\(Int((target.number * 100).rounded())) % FTP" }
            return ftp.map { "\(Int((target.number / $0 * 100).rounded())) % FTP" } ?? "\(Int(target.number.rounded())) W"
        }
        let range = step.end.map { "\(text(step.start)) → \(text($0))" } ?? text(step.start)
        return ftp == nil && isPercent ? "Needs an FTP for watts. Now \(range)." : "≈ \(range)" + (ftp.map { " at \(Int($0.rounded())) W FTP" } ?? "")
    }
}

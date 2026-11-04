import Foundation

/// The workout builder's state, with its two editors (blocks and text) and the rules for switching between them.
/// In Blocks mode the blocks are the state; in Text mode the text is. Neither is converted lossily: switching from
/// Blocks prints the blocks (always possible), and switching from Text parses it, staying in Text mode when it has errors.
public struct BuilderState: Equatable, Sendable {
    public enum Mode: String, Sendable { case blocks, text }

    public private(set) var mode: Mode
    public var name: String
    public var category: WorkoutCategory?
    public private(set) var blocks: [CustomWorkout.Block]
    public private(set) var text: String
    /// The parse of `text`, kept current while editing in Text mode.
    public private(set) var parsed: WorkoutText.Result
    /// The last blocks that parsed cleanly, so the chart has something to show while the text has errors.
    public private(set) var lastValidBlocks: [CustomWorkout.Block]
    /// Why a switch to Blocks mode did not happen.
    public private(set) var notice: String?
    private let original: CustomWorkout

    public init(workout: CustomWorkout, mode: Mode = .blocks) {
        original = workout
        self.mode = mode; name = workout.name; category = workout.category
        blocks = workout.blocks; lastValidBlocks = workout.blocks
        text = WorkoutText.print(workout.blocks); parsed = WorkoutText.parse(text)
    }

    // MARK: Editing

    public mutating func setBlocks(_ value: [CustomWorkout.Block]) {
        guard mode == .blocks else { return }
        blocks = value; lastValidBlocks = value; notice = nil
    }
    public mutating func setText(_ value: String) {
        guard mode == .text else { return }
        text = value; parsed = WorkoutText.parse(value); notice = nil
        if parsed.isValid { lastValidBlocks = parsed.blocks }
    }

    // MARK: Switching

    /// Returns whether the mode changed. Text with errors keeps the rider in Text mode and says which line to fix.
    @discardableResult public mutating func switchTo(_ target: Mode) -> Bool {
        guard target != mode else { return true }
        switch target {
        case .text:
            text = WorkoutText.print(blocks); parsed = WorkoutText.parse(text); mode = .text; notice = nil
            return true
        case .blocks:
            parsed = WorkoutText.parse(text)
            guard parsed.isValid else {
                notice = parsed.errors.first.map { "Fix line \($0.line) first: \($0.message)" }
                return false
            }
            blocks = parsed.blocks; lastValidBlocks = blocks; mode = .blocks; notice = nil
            return true
        }
    }

    // MARK: Reading

    /// What the chart and the summary show: the blocks, or in Text mode the last text that parsed.
    public var shownBlocks: [CustomWorkout.Block] {
        mode == .blocks ? blocks : (parsed.isValid ? parsed.blocks : lastValidBlocks)
    }
    /// The text has errors, so what the chart shows is out of date.
    public var chartIsStale: Bool { mode == .text && !parsed.isValid }
    public func workout(riderID: UUID? = nil, date: Date = Date()) -> CustomWorkout {
        CustomWorkout(id: original.id, riderID: riderID ?? original.riderID, name: CustomWorkout.normalized(name), category: category,
                      blocks: shownBlocks, updatedAt: date)
    }
    /// Reasons Save is disabled, in the words shown under the editor. Empty means it can be saved.
    public var saveBlockers: [String] {
        if mode == .text, !parsed.isValid { return parsed.errors.map { "Line \($0.line): \($0.message)" } }
        return workout().issues()
    }
    public var canSave: Bool { saveBlockers.isEmpty }
    /// Anything the rider changed since the editor opened (asks before closing).
    public var hasUnsavedChanges: Bool {
        let now = workout(date: original.updatedAt)
        return now.name != original.name || now.category != original.category || now.blocks != original.blocks || (mode == .text && !parsed.isValid)
    }
}

import Foundation
import Testing
import FTPunkDomain
import FTPunkStorage
@testable import FTPunkApp

private func example() throws -> Data {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    return try Data(contentsOf: root.appendingPathComponent("contracts/workout-example.zwo"))
}
private func zwo(_ steps: String, sport: String = "<sportType>bike</sportType>", name: String = "<name>Test</name>") -> Data {
    Data("<?xml version=\"1.0\"?><workout_file>\(name)\(sport)<workout>\(steps)</workout></workout_file>".utf8)
}
private func message(_ operation: () throws -> Any) -> String {
    do { _ = try operation(); return "" } catch { return error.localizedDescription }
}

@Test func theExampleExpandsEveryElementAtTheRidersFTP() throws {
    let plan = try ZWOImport.parse(example(), ftp: 250)
    #expect(plan.name == "ZWO example" && plan.ftpWatts == 250 && plan.kind == .workout)
    // Warmup, SteadyState, Ramp, 3 x (on + off), 2 x (on + off), SolidState, Cooldown.
    #expect(plan.steps.count == 3 + 6 + 4 + 2)
    #expect(plan.steps[0] == .init("Warm-up", seconds: 300, watts: 125, endWatts: 188))
    #expect(plan.steps[1] == .init("Steady", seconds: 120, watts: 163))
    #expect(plan.steps[2] == .init("Ramp", seconds: 120, watts: 175, endWatts: 238))
    #expect(plan.steps[3] == .init("On", seconds: 180, watts: 263) && plan.steps[4] == .init("Off", seconds: 120, watts: 138))
    #expect(plan.steps[9] == .init("On", seconds: 60, watts: 225, endWatts: 300) && plan.steps[10] == .init("Off", seconds: 60, watts: 150, endWatts: 125))
    #expect(plan.steps[13] == .init("Steady", seconds: 60, watts: 200))
    #expect(plan.steps.last == .init("Cool-down", seconds: 300, watts: 188, endWatts: 100)) // PowerLow is where it starts
    let expectedDuration: Double = 300 + 120 + 120 + 900 + 240 + 60 + 300
    #expect(plan.duration == expectedDuration)
    #expect(plan.version == 2) // it has ramps
}

@Test func anImportWithoutAnFTPSaysSo() {
    #expect(message { try ZWOImport.parse(zwo(#"<SteadyState Duration="60" Power="0.5"/>"#), ftp: nil) } == "Set an FTP first: ZWO powers are fractions of FTP.")
    #expect(message { try ZWOImport.parse(zwo(#"<SteadyState Duration="60" Power="0.5"/>"#), ftp: 0) }.contains("Set an FTP first"))
}

@Test func unsupportedAndMalformedFilesAreRejectedWithAClearMessage() throws {
    let free = zwo(#"<SteadyState Duration="60" Power="0.5"/><FreeRide Duration="600"/>"#)
    #expect(message { try ZWOImport.parse(free, ftp: 250) }.contains("free-ride or maximal-effort"))
    #expect(message { try ZWOImport.parse(zwo(#"<MaxEffort Duration="30"/>"#), ftp: 250) }.contains("maximal-effort"))
    #expect(message { try ZWOImport.parse(zwo(#"<SolidState Duration="30"/>"#), ftp: 250) }.contains("no power target"))
    #expect(message { try ZWOImport.parse(zwo(#"<SteadyState Duration="60" Power="0.5"/>"#, sport: "<sportType>run</sportType>"), ftp: 250) } == "Only cycling (bike) workouts are supported.")
    #expect(message { try ZWOImport.parse(zwo(#"<SteadyState Duration="60" Power="0.5"/>"#, sport: ""), ftp: 250) } == "") // absent sportType is fine
    for broken in ["", "not xml", "<workout_file><workout><SteadyState Duration=\"60\" Power=\"0.5\"/></workout>", "<other/>",
                   "<!DOCTYPE workout_file [<!ENTITY a \"b\">]><workout_file><workout/></workout_file>"] {
        #expect(message { try ZWOImport.parse(Data(broken.utf8), ftp: 250) } == "This is not a valid ZWO workout file.", "\(broken)")
    }
    #expect(message { try ZWOImport.parse(zwo(""), ftp: 250) } == "The workout contains no steps.")
    // Powers that are not fractions (a rider typed watts) and missing attributes never turn into guessed watts.
    #expect(message { try ZWOImport.parse(zwo(#"<SteadyState Duration="60" Power="200"/>"#), ftp: 250) }.contains("fractions of FTP"))
    #expect(message { try ZWOImport.parse(zwo(#"<SteadyState Duration="60"/>"#), ftp: 250) }.contains("fractions of FTP"))
    #expect(message { try ZWOImport.parse(zwo(#"<Ramp Duration="60" PowerLow="0.5"/>"#), ftp: 250) }.contains("fractions of FTP"))
    #expect(message { try ZWOImport.parse(zwo(#"<SteadyState Power="0.5"/>"#), ftp: 250) }.contains("timed power"))
    #expect(message { try ZWOImport.parse(zwo(#"<SteadyState Duration="-5" Power="0.5"/>"#), ftp: 250) }.contains("timed power"))
}

@Test func theLimitsMatchTheJSONImport() throws {
    #expect(message { try ZWOImport.parse(zwo(#"<IntervalsT Repeat="101" OnDuration="10" OffDuration="10" OnPower="1" OffPower="0.5"/>"#), ftp: 250) } == "Invalid repeat count.")
    #expect(message { try ZWOImport.parse(zwo(#"<IntervalsT Repeat="0" OnDuration="10" OffDuration="10" OnPower="1" OffPower="0.5"/>"#), ftp: 250) } == "Invalid repeat count.")
    // 100 repeats of on + off is 200 steps: fine. Three such blocks are 600 expanded steps: too many.
    let block = #"<IntervalsT Repeat="100" OnDuration="10" OffDuration="10" OnPower="1" OffPower="0.5"/>"#
    #expect(try ZWOImport.parse(zwo(block + block), ftp: 250).steps.count == 400)
    #expect(message { try ZWOImport.parse(zwo(block + block + block), ftp: 250) }.contains("too large"))
    // 24 hours in total, and a single step may not exceed it either.
    #expect(message { try ZWOImport.parse(zwo(#"<SteadyState Duration="86401" Power="0.5"/>"#), ftp: 250) }.contains("timed power"))
    #expect(message { try ZWOImport.parse(zwo(#"<SteadyState Duration="86000" Power="0.5"/><SteadyState Duration="86000" Power="0.5"/>"#), ftp: 250) }.contains("too large"))
    // Over 2 MiB.
    let big = Data(repeating: UInt8(ascii: " "), count: WorkoutImport.maximumBytes) + zwo(#"<SteadyState Duration="60" Power="0.5"/>"#)
    #expect(message { try ZWOImport.parse(big, ftp: 250) } == "Workout files must be under 2 MB.")
}

@Test func everyCatalogWorkoutSurvivesAZWORoundTripWithinOneWatt() throws {
    for definition in WorkoutLibrary.catalog {
        for ftp in [180.0, 250, 333] {
            let original = try definition.plan(ftp: ftp)
            let file = try ZWOExport.data(original, ftp: nil)
            let imported = try ZWOImport.parse(file, ftp: ftp)
            #expect(imported.name == original.name && imported.steps.count == original.steps.count, "\(definition.id)")
            for (a, b) in zip(original.steps, imported.steps) {
                #expect(a.seconds == b.seconds && abs(a.watts - b.watts) <= 1 && (a.endWatts == nil) == (b.endWatts == nil), "\(definition.id) \(a) vs \(b)")
                if let x = a.endWatts, let y = b.endWatts { #expect(abs(x - y) <= 1) }
            }
            #expect(imported.duration == original.duration)
        }
    }
}

@Test func exportUsesThePlansFTPOrTheRidersAndEscapesText() throws {
    let plan = try TrainingPlan(kind: .workout, name: "Over & <under> \"x\"", ftpWatts: 200, steps: [.init("a", seconds: 60, watts: 150), .init("b", seconds: 90.4, watts: 100, endWatts: 250)])
    let text = String(decoding: try ZWOExport.data(plan, ftp: 999), as: UTF8.self)
    #expect(text.contains("<sportType>bike</sportType>") && text.contains("<author>FTPunk</author>"))
    #expect(text.contains("<name>Over &amp; &lt;under&gt; &quot;x&quot;</name>"))
    #expect(text.contains(#"<SteadyState Duration="60" Power="0.750"/>"#))                       // the plan's 200 W, not the rider's 999
    #expect(text.contains(#"<Ramp Duration="90" PowerLow="0.500" PowerHigh="1.250"/>"#))
    let watts = try TrainingPlan(kind: .workout, name: "Plain", steps: [.init("a", seconds: 60, watts: 150)])
    #expect(String(decoding: try ZWOExport.data(watts, ftp: 300), as: UTF8.self).contains(#"Power="0.500""#))
    #expect(message { try ZWOExport.data(watts, ftp: nil) }.contains("Set an FTP first"))
    #expect(message { try ZWOExport.data(TrainingPlan.resistanceRide(level: 50), ftp: 250) }.contains("timed power"))
    #expect(ZWOExport.fileName(for: plan) == "FTPunk-Over-under-x.zwo")
    // The text is well-formed XML.
    #expect(XMLParser(data: Data(text.utf8)).parse())
}

@Test @MainActor func theLibraryImportPicksTheParserByContent() throws {
    let model = try AppModel(store: LocalStore(inMemory: true), preview: true)   // the preview rider has FTP 250
    model.importWorkout(try example())
    #expect(model.errorMessage == nil)
    let imported = try #require(model.catalog.cached.first)
    #expect(imported.source == "Imported ZWO" && imported.plan.steps.count == 15 && imported.plan.ftpWatts == 250)
    model.importWorkout(Data(WorkoutImport.exampleJSON.utf8))
    #expect(model.catalog.cached.contains { $0.source == "Imported JSON" })
    // Without an FTP a ZWO import explains what is missing and saves nothing.
    let bare = try AppModel(store: LocalStore(inMemory: true), preview: true)
    bare.manualFTP = ""; bare.ftpSelection = "none"
    bare.importWorkout(try example())
    #expect(bare.errorMessage == "Set an FTP first: ZWO powers are fractions of FTP." && bare.catalog.cached.isEmpty)
}

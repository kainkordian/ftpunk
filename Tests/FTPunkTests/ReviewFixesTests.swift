import Foundation
import Testing
import FTPunkDomain
@testable import FTPunkApp

// Rules behind the 2 November 2026 review fixes: chart labels, zones, durations, Home card, devices line, cockpit layout.

// MARK: Result chart labels

private func resultSession() throws -> TestSession {
    var session = TestSession(configuration: try SessionConfiguration())
    session.rampStart = 90; session.rampEnd = 1000; session.cooldownStart = 1000; session.endedAtOffset = 1180
    session.result = FTPResult(bestMinutePower: 290, windowStart: 900, windowEnd: 960)
    return session
}

@Test func shortWarmupBandDropsItsLabelInsteadOfOverlappingTheNextOne() throws {
    let bands = ResultChartModel.bands(for: try resultSession())
    let plotWidth = 300.0, total = 1180.0, character = 6.4
    // Warm-up is 90 s of 1180 s: about 23 pt wide, too narrow for "Warm-up" or "Warm".
    let widths = bands.map { plotWidth * ($0.end - $0.start) / total }
    #expect(widths[0] < 30)
    #expect(ResultChartLayout.fittingLabel(for: "Warm-up", availableWidth: widths[0] - 8, characterWidth: character) == nil)
    #expect(ResultChartLayout.fittingLabel(for: "Ramp", availableWidth: widths[1] - 8, characterWidth: character) == "Ramp")
    // Cool-down is 180 s: about 46 pt, so it gets the short form.
    #expect(ResultChartLayout.fittingLabel(for: "Cool-down", availableWidth: widths[2] - 8, characterWidth: character) == "Cool")
}

@Test func phaseLabelsNeverOverlapAtAnyPlotWidthOrDurationMix() throws {
    let bands = ResultChartModel.bands(for: try resultSession())
    let total = 1180.0, character = 6.4
    for plotWidth in stride(from: 80.0, through: 700.0, by: 10) {
        var previousEnd = -Double.infinity
        for band in bands {
            let start = plotWidth * band.start / total, end = plotWidth * band.end / total
            guard let text = ResultChartLayout.fittingLabel(for: band.title, availableWidth: end - start - 8, characterWidth: character) else { continue }
            let labelStart = start + 4, labelEnd = labelStart + ResultChartLayout.estimatedWidth(of: text, characterWidth: character)
            #expect(labelStart >= previousEnd, "\(band.title) at \(plotWidth) pt")
            #expect(labelEnd <= end, "\(band.title) stays inside its band at \(plotWidth) pt")
            previousEnd = labelEnd
        }
    }
}

@Test func labelFormsShrinkBeforeTheyDisappear() {
    #expect(ResultChartLayout.candidates(for: "Warm-up") == ["Warm-up", "Warm"])
    #expect(ResultChartLayout.candidates(for: "Cool-down") == ["Cool-down", "Cool"])
    #expect(ResultChartLayout.candidates(for: "Best minute 290 W") == ["Best minute 290 W", "Best 290 W"])
    #expect(ResultChartLayout.fittingLabel(for: "Warm-up", availableWidth: 30, characterWidth: 6.4) == "Warm")
    #expect(ResultChartLayout.fittingLabel(for: "Warm-up", availableWidth: 10, characterWidth: 6.4) == nil)
    #expect(ResultChartLayout.fittingLabel(for: "Ramp", availableWidth: .nan, characterWidth: 6.4) == nil)
}

@Test func bestMinuteLabelStaysInsideThePlot() {
    // Centred when there is room, pushed in at either edge, left-aligned when the plot is narrower than the label.
    #expect(ResultChartLayout.clampedLeading(centre: 150, width: 100, plotWidth: 300) == 100)
    #expect(ResultChartLayout.clampedLeading(centre: 10, width: 100, plotWidth: 300) == 0)
    #expect(ResultChartLayout.clampedLeading(centre: 295, width: 100, plotWidth: 300) == 200)
    #expect(ResultChartLayout.clampedLeading(centre: 50, width: 400, plotWidth: 300) == 0)
    #expect(ResultChartLayout.clampedLeading(centre: .nan, width: 100, plotWidth: 300) == 0)
}

@Test func chartKeepsHeadroomForTwoLabelRows() {
    #expect(ResultChartLayout.ceiling(forPeak: 290) > 290 * 1.3)
    #expect(ResultChartLayout.ceiling(forPeak: 0) >= 100 && ResultChartLayout.ceiling(forPeak: .nan) >= 100)
}

@Test func resultPowerLineHasThreeToOneContrastOnThePlotInBothThemes() {
    // The line is the accent: dark green on light surfaces, lime on dark ones (it used to be the pale-lime tint on light grey).
    func blend(_ colour: ActionRGB, over background: ActionRGB, alpha: Double) -> ActionRGB {
        ActionRGB(red: colour.red * alpha + background.red * (1 - alpha), green: colour.green * alpha + background.green * (1 - alpha),
                  blue: colour.blue * alpha + background.blue * (1 - alpha))
    }
    let secondaryLight = ActionRGB(red: 0.28, green: 0.31, blue: 0.29), secondaryDark = ActionRGB(red: 0.74, green: 0.78, blue: 0.75)
    for (line, page, secondary, dark) in [(Theme.accentPair.light, ActionRGB(red: 1, green: 1, blue: 1), secondaryLight, false),
                                          (Theme.accentPair.dark, ActionRGB(red: 0, green: 0, blue: 0), secondaryDark, true)] {
        let card = blend(ActionRGB(red: dark ? 1 : 0, green: dark ? 1 : 0, blue: dark ? 1 : 0), over: page, alpha: 0.07)
        var backgrounds = [page, card]
        for alpha in [0.10, 0.18] { backgrounds.append(blend(secondary, over: card, alpha: alpha)) }       // phase bands
        backgrounds.append(blend(line, over: card, alpha: 0.24))                                          // best-minute band
        for background in backgrounds { #expect(line.contrast(with: background) >= 3, "\(dark ? "dark" : "light") plot") }
    }
}

// MARK: Zones and profile scale

@Test func zonesFollowThePublishedPercentBands() {
    func zone(_ percent: Double) -> IntensityZone { IntensityZone.zone(forFraction: percent / 100) }
    #expect(zone(0) == .recovery && zone(55) == .recovery && zone(55.4) == .recovery)
    #expect(zone(56) == .endurance && zone(75) == .endurance)
    #expect(zone(76) == .tempo && zone(87) == .tempo)
    #expect(zone(88) == .sweetSpot && zone(94) == .sweetSpot)
    #expect(zone(95) == .threshold && zone(105) == .threshold)
    #expect(zone(106) == .vo2max && zone(150) == .vo2max)
    #expect(IntensityZone.zone(forFraction: .infinity) == .vo2max && IntensityZone.zone(forFraction: .nan) == .recovery)
    #expect(IntensityZone.allCases.sorted() == IntensityZone.allCases)
}

@Test func profileHeightsUseOneFixedScaleSoIntensityIsComparableAcrossWorkouts() throws {
    func plan(_ percent: Double, ftp: Double = 250) throws -> TrainingPlan {
        try TrainingPlan(kind: .workout, name: "Set", ftpWatts: ftp, steps: [.init("Hard", seconds: 600, watts: Int((ftp * percent / 100).rounded()))])
    }
    let tempo = try WorkoutProfile.bars(for: plan(80)), vo2 = try WorkoutProfile.bars(for: plan(115))
    #expect(tempo[0].zone == .tempo && vo2[0].zone == .vo2max)
    #expect(abs(tempo[0].startHeight - 80 / 130) < 0.01 && abs(vo2[0].startHeight - 115 / 130) < 0.01)
    #expect(vo2[0].startHeight > tempo[0].startHeight)
    // A different FTP changes the watts, not the picture.
    #expect(try abs(WorkoutProfile.bars(for: plan(115, ftp: 180))[0].startHeight - vo2[0].startHeight) < 0.01)
    // Above 130 % the bar is clamped to the top of the scale.
    #expect(try WorkoutProfile.bars(for: plan(160))[0].startHeight == 1)
}

@Test func rampsKeepTheirSlopeAndNoFTPMeansNeutral() throws {
    let ramp = try TrainingPlan(kind: .workout, name: "Ramp", ftpWatts: 200, steps: [.init("Warm-up", seconds: 600, watts: 100, endWatts: 140), .init("Hold", seconds: 300, watts: 200)])
    let bars = WorkoutProfile.bars(for: ramp)
    #expect(bars[0].startHeight < bars[0].endHeight && abs(bars[0].start) < 1e-9 && abs(bars[0].end - 600.0 / 900) < 1e-9)
    #expect(bars[0].zone == .endurance && bars[1].zone == .threshold)
    let free = try TrainingPlan(kind: .workout, name: "Imported", steps: [.init("Easy", seconds: 300, watts: 100), .init("Hard", seconds: 300, watts: 200)])
    let neutral = WorkoutProfile.bars(for: free)
    #expect(neutral.allSatisfy { $0.zone == nil })
    #expect(neutral[1].startHeight == 1 && abs(neutral[0].startHeight - 0.5) < 1e-9) // relative to the plan's own peak
    // Intensity scales the bars: 110 % of a 90 % set is a 99 % set.
    let sweet = try TrainingPlan(kind: .workout, name: "SS", ftpWatts: 200, steps: [.init("SS", seconds: 600, watts: 180)])
    #expect(WorkoutProfile.bars(for: sweet)[0].zone == .sweetSpot && WorkoutProfile.bars(for: sweet, intensity: 110)[0].zone == .threshold)
}

@Test func zoneColoursClimbInLightnessAndHaveContrastInBothThemes() {
    var previousLight = Double.infinity, previousDark = 0.0
    for zone in IntensityZone.allCases {
        let pair = ZonePalette.pair(for: zone)
        #expect(pair.light.contrast(with: ZonePalette.lightBackground) >= 3, "\(zone.title) on light")
        #expect(pair.dark.contrast(with: ZonePalette.darkBackground) >= 3, "\(zone.title) on dark")
        // Neighbouring zones differ in lightness (by at least ~12 %), not only in hue; the direction is the same for every zone.
        #expect((previousLight + 0.05) / (pair.light.luminance + 0.05) >= 1.12 || previousLight == .infinity, "\(zone.title) light step")
        #expect((pair.dark.luminance + 0.05) / (previousDark + 0.05) >= 1.12 || previousDark == 0, "\(zone.title) dark step")
        previousLight = pair.light.luminance; previousDark = pair.dark.luminance
    }
}

// MARK: Durations

@Test func workoutDurationsShowMinutesBelowTwoHours() {
    #expect(DurationFormat.workout(3600) == "60 min")
    #expect(DurationFormat.workout(95 * 60) == "95 min")
    #expect(DurationFormat.workout(119 * 60) == "119 min")
    #expect(DurationFormat.workout(120 * 60) == "2 h")
    #expect(DurationFormat.workout(135 * 60) == "2 h 15 min")
    #expect(DurationFormat.workout(185 * 60) == "3 h 05 min")
    #expect(DurationFormat.workout(45) == "45 s" && DurationFormat.workout(.nan) == "—" && DurationFormat.workout(-1) == "—")
    #expect(DurationFormat.compact(3900) == "1 h 05 min") // the general format is unchanged
}

// MARK: Home card, chip, devices

@Test func ftpStatusLineMergesDateAndAgeAndBecomesTheRetestPrompt() {
    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "UTC")!
    let now = Date(timeIntervalSince1970: 1_800_000_000) // 15 January 2027
    func ago(_ days: Int) -> Date { now.addingTimeInterval(-Double(days) * 86400) }
    let recent = FTPStatusLine.make(date: ago(21), isRamp: true, source: "Ramp test", now: now, calendar: calendar)
    #expect(recent.text == "Tested 25 Dec · 3 weeks ago" && !recent.isRetestPrompt)
    let due = FTPStatusLine.make(date: ago(63), isRamp: true, source: "Ramp test", now: now, calendar: calendar)
    #expect(due.text == "Tested 13 Nov · 9 weeks ago · time to retest?" && due.isRetestPrompt)
    #expect(FTPStatusLine.make(date: ago(2), isRamp: true, source: "Ramp test", now: now, calendar: calendar).text == "Tested 13 Jan · this week")
    #expect(FTPStatusLine.make(date: ago(7), isRamp: false, source: "Manual entry", now: now, calendar: calendar).text == "Set 8 Jan · 1 week ago · Manual entry")
    #expect(FTPStatusLine.make(date: nil, isRamp: false, source: "Entered for this ride", now: now, calendar: calendar) == FTPStatusLine(text: "Entered for this ride", isRetestPrompt: false))
    #expect(RetestAdvice.recent(weeks: 1).ageText == "1 week ago" && RetestAdvice.never.ageText == nil)
}

@Test func riderChipNameTruncatesLongNamesAndKeepsShortOnes() {
    #expect(RiderChipName.display("Alex") == "Alex")
    #expect(RiderChipName.display("  Alex  ") == "Alex")
    #expect(RiderChipName.display("Alexandria-Marguerite von Hohenberg") == "Alexandria-Ma…")
    #expect(RiderChipName.display("Alexandria-Marguerite von Hohenberg").count == RiderChipName.maximumCharacters)
    #expect(RiderChipName.display("Exactly14chars") == "Exactly14chars")
    #expect(RiderChipName.display("Sam Jones the Third", limit: 6) == "Sam J…")
    #expect(RiderChipName.display("") == "")
}

@Test func devicesLineLabelsEveryPartSoItCannotContradictItself() {
    #expect(DevicesLine.make(trainerName: nil, powerSource: .trainer, meterName: nil, heartRateName: nil) == "Trainer: not connected · Power: from trainer · Heart rate: none")
    #expect(DevicesLine.make(trainerName: "KICKR", powerSource: .externalPowerMeter, meterName: "Favero", heartRateName: "H10") == "Trainer: KICKR · Power: from Favero · Heart rate: H10")
    #expect(DevicesLine.make(trainerName: "KICKR", powerSource: .externalPowerMeter, meterName: nil, heartRateName: nil).contains("Power: from external meter"))
}

// MARK: Cockpit layout

@Test func cockpitLayoutIsCompactAtAccessibilitySizesAndDropsTheCoachingLineMidRamp() {
    let regular = CockpitLayout.make(phase: .ramp, accessibilitySize: false)
    #expect(!regular.compactHeader && regular.showsHeaderSubtitle && regular.showsTimelineLabels && !regular.metricRows)
    #expect(!regular.showsCoachingLine) // the bottom bar clipped it mid-ramp
    #expect(CockpitLayout.make(phase: .warmup, accessibilitySize: false).showsCoachingLine)
    #expect(CockpitLayout.make(phase: .cooldown, accessibilitySize: false).showsCoachingLine)
    let large = CockpitLayout.make(phase: .warmup, accessibilitySize: true)
    #expect(large.compactHeader && !large.showsHeaderSubtitle && !large.showsTimelineLabels && large.metricRows && !large.showsCoachingLine)
    // Chaindance takes the coaching line's place, so the bottom bar can never clip it.
    #expect(!CockpitLayout.make(phase: .warmup, accessibilitySize: false, rideVisual: .strip).showsCoachingLine)
    #expect(!CockpitLayout.make(phase: .cooldown, accessibilitySize: false, rideVisual: .strip).showsCoachingLine)
    #expect(CockpitLayout.compactClock("8:20", phase: .warmup) == "8:20 left" && CockpitLayout.compactClock("7:20", phase: .ramp) == "7:20")
}

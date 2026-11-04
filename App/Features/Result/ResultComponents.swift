import SwiftUI
import FTPunkDomain

/// The estimate with its change from the current FTP. The stored factor is shown, so recordings
/// made with the older 75 % option keep their original figures.
struct FTPResultCard: View {
    let result: FTPResult
    var currentFTP: Double?
    var showDelta = true
    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text("ESTIMATED FTP").ftpLabel().foregroundStyle(Theme.accent)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: Space.m) { figures }
                VStack(alignment: .leading, spacing: Space.xs) { figures }
            }
            if showDelta {
                let delta = ResultDelta(newFTP: result.estimatedFTP, currentFTP: currentFTP)
                Text(delta.text).font(.headline).foregroundStyle(delta.watts < 0 ? Theme.warning : .primary)
            }
            Text("\(Int((result.factor * 100).rounded())) % of your best minute, \(Int(result.bestMinutePower.rounded())) W")
                .font(.subheadline).foregroundStyle(Theme.secondary)
        }
        .padding(Space.l).frame(maxWidth: .infinity, alignment: .leading).ftpCard(tint: Theme.accent, fill: 0.08)
        .accessibilityElement(children: .combine)
    }
    @ViewBuilder private var figures: some View {
        Text("\(Int(result.estimatedFTP.rounded())) W").ftpNumber(.hero)
        if let wkg = result.wattsPerKG { Text("\(wkg, specifier: "%.2f") W/kg").font(.title3).foregroundStyle(Theme.secondary) }
    }
}

/// "How this is calculated": the shaded minute, the factor and the 72–77 % range.
struct CalculationNote: View {
    let result: FTPResult?
    let showInfo: () -> Void
    var body: some View {
        if let result {
            DisclosureGroup("How this is calculated") {
                VStack(alignment: .leading, spacing: Space.s) {
                    Text("FTPunk takes the best continuous 60 seconds of the scored ramp, shaded above, and uses \(Int((result.factor * 100).rounded())) % of it. Warm-up, cool-down and the low-cadence confirmation period never count.")
                    Text("Research reports one-hour power commonly between 72 % and 77 % of that minute: \(Int(result.lowerFTP.rounded()))–\(Int(result.upperFTP.rounded())) W here. New tests report the conservative 72 %, because underestimating FTP is less harmful than overestimating it.")
                    Button(action: showInfo) { Label("Why 72–77 %?", systemImage: "info.circle") }.buttonStyle(FTPunkRowButtonStyle())
                }.font(.callout).foregroundStyle(Theme.secondary)
            }.font(.subheadline)
        } else {
            Button(action: showInfo) { Label("How an estimate is calculated", systemImage: "info.circle") }.buttonStyle(FTPunkRowButtonStyle())
        }
    }
}

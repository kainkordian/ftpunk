import SwiftUI

enum TestInfo: String, Identifiable {
    case protocols, estimate
    var id: String { rawValue }
}

struct ProtocolInfoView: View {
    let topic: TestInfo
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                if topic == .protocols {
                    Section("Which ramp should I choose?") {
                        Text("15 W/min: a gentler ramp for lighter riders. The reference project's weight guideline is below 60 kg. Start at 50 W and add 5 W every 20 seconds.")
                        Text("25 W/min: the reference option for heavier riders (60 kg and above). Start at 100 W and add 5 W every 12 seconds.")
                        Text("20 W/min · Zwift-style: the legacy option used by apps such as Zwift. Start at 100 W and add 20 W every 60 seconds. FTPunk keeps your chosen warm-up and estimate factor; this is not a reproduction of the entire Zwift workout.")
                    }
                    Section("Why the 15 and 25 W protocols?") {
                        Text("The reference follows coach Richard Stern's MAP method. He recommended different ramp rates and the smallest practical increments, rather than one universal ramp. He argues that changing the protocol changes the MAP result and therefore the FTP estimate.")
                        Text("His original guidance distinguishes non-elite men (25 W/min), elite men (20 W/min), and women (15 W/min). The 60 kg light/heavy shortcut comes from this reference project. It is a practical guideline, not a universal physiological boundary. Choose manually and use the same protocol for comparisons.")
                    }
                    Section("Warm-up") {
                        Text("With an existing FTP, the default warm-up target is 50% of that value. Without one, the reference uses 75 W for the lighter protocol and 100 W for the heavier protocol. You can override the target.")
                    }
                    Link("Richard Stern · MAP protocol and FTP", destination: Self.source)
                    Link("Zwift · its 20 W/min ramp", destination: URL(string: "https://www.zwift.com/ca/news/32912-how-to-measure-your-cycling-fitness-effectively")!)
                } else {
                    Section("An estimate, with a range") {
                        Text("FTPunk takes the best continuous 60 seconds from your selected power source during the scored ramp as its MAP proxy. Warm-up, cooldown and any low-cadence confirmation period are excluded.")
                        Text("Stern reports that roughly one-hour power commonly fell between 72% and 77% of MAP in the riders he studied. This is a guideline range, not a personal confidence interval or a guarantee.")
                        Text("75% became a common single-number estimate in training apps. Stern recommends 72% as a conservative starting point when a longer test is unavailable. FTPunk defaults to 72%, offers 75%, and always shows the 72–77% range.")
                    }
                    Section("Example") {
                        Text("A best minute of 300 W gives a range of 216–231 W. The 72% estimate is 216 W; the 75% estimate is 225 W. W/kg divides the chosen estimate by the weight saved with that test.")
                    }
                    Section("Use the result") {
                        Text("Anaerobic contribution and endurance vary between riders. Check whether the estimate fits sustainable training efforts or compare it with a longer test. Keep the protocol and factor consistent when reviewing progress.")
                    }
                    Link("Read Stern's explanation", destination: Self.source)
                }
            }
            .navigationTitle(topic == .protocols ? "Ramp protocols" : "Why 72–77%?")
            .toolbar { Button("Done") { dismiss() } }
        }.frame(minWidth: 320, idealWidth: 540, minHeight: 420)
    }
    private static let source = URL(string: "https://www.cyclecoach.com/blog/2020/2/2/is-the-map-ramp-test-a-valid-estimator-of-ftp")!
}

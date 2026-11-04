import SwiftUI
import UniformTypeIdentifiers
import FTPunkDomain
import FTPunkStorage

/// A finished activity's bytes, handed to the system save panel (macOS) or Files (iOS).
struct ActivityFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.data, .xml, .json, .commaSeparatedText] + ActivityFileFormat.allCases.compactMap { UTType(filenameExtension: $0.rawValue) } }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

extension UTType {
    /// Zwift workout files: XML with the `.zwo` extension.
    static let zwo = UTType(filenameExtension: "zwo", conformingTo: .xml) ?? .xml
}

extension ActivityFileFormat {
    var contentType: UTType {
        switch self {
        case .fit, .tcx: UTType(filenameExtension: rawValue) ?? (self == .tcx ? .xml : .data)
        case .csv: .commaSeparatedText
        case .json: .json
        }
    }
}

/// "Export FIT file" first (for COROS, Garmin, Strava and TrainingPeaks), the other formats in a menu. Used by the activity
/// detail and the result screen, so both go through the same code.
struct ActivityExportControls: View {
    @Bindable var model: AppModel
    let session: TestSession
    @State private var document: ActivityFileDocument?
    @State private var format = ActivityFileFormat.fit
    @State private var fileName = ""
    @State private var saving = false
    @State private var prepared: (url: URL, format: ActivityFileFormat, bytes: Int)?

    /// COROS Training Hub accepts files from 20 KB (per COROS support).
    static let corosMinimumBytes = 20_000

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Button { prepare(.fit) } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Export FIT file", systemImage: "square.and.arrow.up")
                    Text("For COROS, Garmin, Strava and TrainingPeaks").font(.footnote).foregroundStyle(Theme.secondary)
                }
            }.accessibilityIdentifier("export-fit")
            Menu("Other formats") {
                ForEach([ActivityFileFormat.tcx, .csv, .json], id: \.self) { other in Button(other.title) { prepare(other) } }
            }
            #if os(iOS)
            if let prepared { ShareLink("Share \(prepared.format.title)", item: prepared.url) }
            #endif
            if let prepared, prepared.format == .fit {
                Text("COROS: open Training Hub → Activity List → Import Data and choose this file.").font(.footnote).foregroundStyle(Theme.secondary)
                // Unverified: the Training Hub address has not been checked by the owner.
                Link("Open COROS Training Hub", destination: URL(string: "https://t.coros.com")!)
                if prepared.bytes < Self.corosMinimumBytes {
                    Text("COROS may reject files under 20 KB. If it does, export TCX instead.").font(.footnote).foregroundStyle(Theme.secondary)
                }
            }
        }
        .fileExporter(isPresented: $saving, document: document, contentType: format.contentType, defaultFilename: fileName) { result in
            if case .failure(let error) = result { model.errorMessage = error.localizedDescription }
        }
    }

    private func prepare(_ chosen: ActivityFileFormat) {
        guard let url = model.export(session, format: chosen), let data = try? Data(contentsOf: url) else { return }
        prepared = (url, chosen, data.count)
        document = ActivityFileDocument(data: data); format = chosen
        fileName = url.deletingPathExtension().lastPathComponent
        saving = true
    }
}

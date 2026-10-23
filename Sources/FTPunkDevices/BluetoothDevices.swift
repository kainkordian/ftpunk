import Foundation
import Observation
import CoreBluetooth
import FTPunkDomain

public enum DeviceRole: String, CaseIterable, Identifiable, Codable, Sendable {
    // Keep the old "pedals" raw value for stored device/capture compatibility.
    // It now covers any supported external Bluetooth Cycling Power meter.
    case trainer, pedals, heartRate
    public var id: String { rawValue }
    public var title: String {
        switch self { case .trainer: "Trainer"; case .pedals: "External power meter"; case .heartRate: "Heart rate" }
    }
    fileprivate var service: CBUUID {
        CBUUID(string: self == .trainer ? "1826" : self == .pedals ? "1818" : "180D")
    }
}

public struct NearbyDevice: Identifiable {
    public let id: UUID
    public var name: String
    public var signal: Int
    public var roles: [DeviceRole]
}

public struct DeviceReading: Sendable {
    public let role: DeviceRole
    public let uptime: Double
    public var power: Double?
    public var cadence: Double?
    public var heartRate: Int?
    public init(role: DeviceRole, uptime: Double, power: Double? = nil, cadence: Double? = nil, heartRate: Int? = nil) {
        self.role = role; self.uptime = uptime; self.power = power; self.cadence = cadence; self.heartRate = heartRate
    }
}

public struct PacketCapture: Codable, Identifiable, Sendable {
    public let id: UUID
    public let date: Date
    public let role: DeviceRole
    public let characteristic: String
    public let hex: String
}

public enum BluetoothError: Error, LocalizedError {
    case notReady, busy, timedOut, rejected(UInt8), disconnected, unsupported, targetOutOfRange
    public var errorDescription: String? {
        switch self {
        case .notReady: "Trainer control is not ready."
        case .busy: "A trainer command is still in progress."
        case .timedOut: "The trainer did not confirm the command. Reconnect before retrying."
        case .rejected(let code): "The trainer rejected the command (result \(code))."
        case .disconnected: "The Bluetooth connection ended."
        case .unsupported: "The trainer does not expose the required ERG controls."
        case .targetOutOfRange: "The target is outside the trainer's supported power range."
        }
    }
}

/// Main-actor delegate isolation serializes this first hardware prototype's low-rate callbacks.
/// The workout core and decoders are independent of UI and CoreBluetooth.
@MainActor @Observable public final class BluetoothDevices: NSObject {
    public private(set) var nearby: [NearbyDevice] = []
    public private(set) var names: [DeviceRole: String] = [:]
    public private(set) var status = "Connect your trainer. An external power meter and heart-rate sensor are optional."
    public private(set) var scanning = false
    public private(set) var trainerCanPrepare = false
    public private(set) var trainerReady = false
    public private(set) var powerRange: SupportedPowerRange?
    public private(set) var measurements = DeviceMeasurements()
    public private(set) var captures: [PacketCapture] = []
    public var captureEnabled = false
    public var resistanceLayout: ResistanceLayout = .standardOneByte
    public var deviceSnapshots: [DeviceSnapshot] {
        selected.map { role, peripheral in
            var capabilities: [String: String] = [:]
            if role == .trainer, let powerRange {
                capabilities = ["minimumWatts": String(powerRange.minimum), "maximumWatts": String(powerRange.maximum),
                                "incrementWatts": String(powerRange.increment), "resistanceLayout": resistanceLayout.rawValue]
            }
            return DeviceSnapshot(role: role.rawValue, name: names[role] ?? role.title,
                                  localIdentifier: peripheral.identifier.uuidString, capabilities: capabilities)
        }
    }
    @ObservationIgnored public var onReading: ((DeviceReading) -> Void)?
    @ObservationIgnored public var onDeviceFailure: ((DeviceRole, String) -> Void)?
    @ObservationIgnored private var central: CBCentralManager?
    @ObservationIgnored private var discovered: [UUID: CBPeripheral] = [:]
    @ObservationIgnored private var selected: [DeviceRole: CBPeripheral] = [:]
    @ObservationIgnored private var characteristics: [String: CBCharacteristic] = [:]
    @ObservationIgnored private var features: FitnessMachineFeatures?
    @ObservationIgnored private var controlHealthy = true
    @ObservationIgnored private var cadenceTracker = CadenceTracker()
    @ObservationIgnored private var pending: (id: UUID, opcode: UInt8, continuation: CheckedContinuation<Void, any Error>)?
    @ObservationIgnored private var timeout: Task<Void, Never>?

    public override init() { super.init() }

    public func scan() {
        if central == nil { central = CBCentralManager(delegate: self, queue: .main); return }
        guard central?.state == .poweredOn else { status = "Enable Bluetooth and allow access in Settings."; return }
        central?.scanForPeripherals(withServices: DeviceRole.allCases.map(\.service))
        scanning = true; status = "Searching for Bluetooth devices…"
    }

    public func stopScanning() { central?.stopScan(); scanning = false }

    public func connect(_ device: NearbyDevice, as role: DeviceRole) {
        guard let peripheral = discovered[device.id] else { return }
        guard !selected.contains(where: { $0.key != role && $0.value.identifier == device.id }) else {
            status = "Use the trainer as the power source, or select a separate external power meter."; return
        }
        if let old = selected[role] {
            selected.removeValue(forKey: role); central?.cancelPeripheralConnection(old)
        }
        if role == .trainer { clearTrainer() }
        if role == .pedals { clearPedals() }
        selected[role] = peripheral; peripheral.delegate = self
        status = "Connecting \(device.name)…"
        central?.connect(peripheral)
    }

    public func disconnect(_ role: DeviceRole) {
        guard let peripheral = selected.removeValue(forKey: role) else { return }
        names.removeValue(forKey: role)
        if role == .trainer { clearTrainer() }
        if role == .pedals { clearPedals() }
        central?.cancelPeripheralConnection(peripheral)
        onDeviceFailure?(role, "\(role.title) disconnected.")
    }

    public func prepareTrainer() async throws {
        guard trainerCanPrepare else { throw BluetoothError.notReady }
        try await command(.requestControl)
        trainerReady = true; status = "Trainer control confirmed."
    }

    public func startTrainer(power: Int) async throws {
        guard trainerReady else { throw BluetoothError.notReady }
        try await command(.start)
        try await setTargetPower(power)
    }

    public func setTargetPower(_ watts: Int) async throws {
        guard trainerReady, let powerRange else { throw BluetoothError.notReady }
        guard watts >= powerRange.minimum, watts <= powerRange.maximum else { throw BluetoothError.targetOutOfRange }
        try await command(.targetPower(powerRange.quantized(watts)))
    }

    public func stopTrainer() async throws {
        // Let an in-flight transaction finish before the stop procedure; never interleave FTMS commands.
        for _ in 0..<60 where pending != nil { try await Task.sleep(for: .milliseconds(100)) }
        try await command(.stop)
    }

    private func command(_ command: TrainerCommand) async throws {
        guard let trainer = selected[.trainer], trainer.state == .connected,
              let control = characteristics["2AD9"], control.isNotifying else { throw BluetoothError.notReady }
        guard pending == nil else { throw BluetoothError.busy }
        let data = try command.encoded(), id = UUID()
        try await withCheckedThrowingContinuation { continuation in
            pending = (id, command.opcode, continuation)
            timeout = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
                guard let self, self.pending?.id == id else { return }
                self.trainerReady = false; self.trainerCanPrepare = false; self.controlHealthy = false
                self.resolve(.failure(BluetoothError.timedOut))
                self.onDeviceFailure?(.trainer, BluetoothError.timedOut.localizedDescription)
            }
            trainer.writeValue(data, for: control, type: .withResponse)
        }
    }

    private func resolve(_ result: Result<Void, any Error>) {
        timeout?.cancel(); timeout = nil
        let continuation = pending?.continuation; pending = nil
        continuation?.resume(with: result)
    }
    private func clearTrainer() {
        resolve(.failure(BluetoothError.disconnected))
        trainerReady = false; trainerCanPrepare = false; powerRange = nil; features = nil; controlHealthy = true
        characteristics = [:]
        measurements.reset(.trainer)
    }
    private func clearPedals() {
        cadenceTracker.reset()
        measurements.reset(.pedals)
    }
    private func role(of peripheral: CBPeripheral) -> DeviceRole? {
        selected.first { $0.value === peripheral }?.key
    }
    private func updateReadiness() {
        trainerCanPrepare = controlHealthy && features?.supportsTargetPower == true && powerRange != nil &&
            characteristics["2AD9"]?.isNotifying == true && characteristics["2AD2"]?.isNotifying == true &&
            characteristics["2ADA"]?.isNotifying == true
    }
    private func failure(_ error: any Error, role: DeviceRole) {
        status = error.localizedDescription
        measurements.reset(role)
        if role == .trainer { trainerReady = false }
        onDeviceFailure?(role, status)
    }
}

extension BluetoothDevices: @preconcurrency CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn { scan() }
        else {
            names = [:]; clearTrainer(); clearPedals(); scanning = false
            status = "Bluetooth is unavailable. Check Bluetooth permission and Settings."
            onDeviceFailure?(.trainer, status)
        }
    }
    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                               advertisementData: [String: Any], rssi RSSI: NSNumber) {
        discovered[peripheral.identifier] = peripheral
        let services = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        let roles = DeviceRole.allCases.filter { services.contains($0.service) }
        let value = NearbyDevice(id: peripheral.identifier,
                                 name: peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? "Bluetooth sensor",
                                 signal: RSSI.intValue, roles: roles)
        if let index = nearby.firstIndex(where: { $0.id == value.id }) { nearby[index] = value }
        else { nearby.append(value) }
    }
    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard let role = role(of: peripheral) else { central.cancelPeripheralConnection(peripheral); return }
        names[role] = peripheral.name ?? role.title
        peripheral.discoverServices([role.service])
        status = "Discovering \(role.title.lowercased()) services…"
    }
    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: (any Error)?) {
        guard let role = role(of: peripheral) else { return }
        failure(error ?? BluetoothError.disconnected, role: role)
    }
    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: (any Error)?) {
        guard let role = role(of: peripheral) else { return }
        names.removeValue(forKey: role)
        if role == .trainer { clearTrainer() }
        if role == .pedals { clearPedals() }
        failure(error ?? BluetoothError.disconnected, role: role)
    }
}

extension BluetoothDevices: @preconcurrency CBPeripheralDelegate {
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        guard let role = role(of: peripheral) else { return }
        if let error { failure(error, role: role); return }
        guard let service = peripheral.services?.first(where: { $0.uuid == role.service }) else {
            failure(BluetoothError.unsupported, role: role); return
        }
        peripheral.discoverCharacteristics(nil, for: service)
    }
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: (any Error)?) {
        guard let role = role(of: peripheral) else { return }
        if let error { failure(error, role: role); return }
        for characteristic in service.characteristics ?? [] {
            let uuid = characteristic.uuid.uuidString
            if role == .trainer {
                characteristics[uuid] = characteristic
                if ["2ACC", "2AD8"].contains(uuid) { peripheral.readValue(for: characteristic) }
                if ["2AD2", "2AD9", "2ADA"].contains(uuid) { peripheral.setNotifyValue(true, for: characteristic) }
            } else if role == .pedals && uuid == "2A63" || role == .heartRate && uuid == "2A37" {
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
        updateReadiness()
    }
    public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: (any Error)?) {
        guard let role = role(of: peripheral) else { return }
        if let error { failure(error, role: role); return }
        status = "\(role.title) notifications ready."
        updateReadiness()
    }
    public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: (any Error)?) {
        guard role(of: peripheral) == .trainer, characteristics["2AD9"] === characteristic else { return }
        if let error { resolve(.failure(error)); failure(error, role: .trainer) }
        // Success only acknowledges the GATT write. Wait for the Control Point indication.
    }
    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: (any Error)?) {
        guard let role = role(of: peripheral) else { return }
        if let error { failure(error, role: role); return }
        guard let data = characteristic.value else { return }
        if captureEnabled {
            captures.append(PacketCapture(id: UUID(), date: Date(), role: role,
                                          characteristic: characteristic.uuid.uuidString,
                                          hex: data.map { String(format: "%02X", $0) }.joined(separator: " ")))
            if captures.count > 500 { captures.removeFirst(captures.count - 500) }
        }
        let time = ProcessInfo.processInfo.systemUptime
        do {
            switch (role, characteristic.uuid.uuidString) {
            case (.trainer, "2ACC"): features = try FitnessMachineFeatures.decode(data)
            case (.trainer, "2AD8"): powerRange = try SupportedPowerRange.decode(data)
            case (.trainer, "2AD9"):
                let response = try ControlResponse.decode(data)
                guard response.requestOpcode == pending?.opcode else { return }
                resolve(response.succeeded ? .success(()) : .failure(BluetoothError.rejected(response.result)))
            case (.trainer, "2ADA"):
                if data.first == 0xff {
                    trainerReady = false; resolve(.failure(BluetoothError.notReady))
                    onDeviceFailure?(.trainer, "Trainer control was taken by another application.")
                }
            case (.trainer, "2AD2"):
                let value = try IndoorBikeData.decode(data, resistanceLayout: resistanceLayout)
                let reading = DeviceReading(role: role, uptime: time, power: value.powerWatts, cadence: value.cadenceRPM)
                measurements.receive(reading); onReading?(reading)
            case (.pedals, "2A63"):
                let value = try CyclingPowerMeasurement.decode(data)
                let cadence = value.crank.flatMap { cadenceTracker.receive($0, at: time) }
                let reading = DeviceReading(role: role, uptime: time, power: value.watts, cadence: cadence)
                measurements.receive(reading); onReading?(reading)
            case (.heartRate, "2A37"):
                onReading?(DeviceReading(role: role, uptime: time, heartRate: try HeartRateMeasurement.decode(data)))
            default: break
            }
            updateReadiness()
        } catch {
            // Malformed measurements are discarded; they never refresh the last valid sample.
            status = "Discarded malformed \(role.title.lowercased()) data."
            if characteristic.uuid.uuidString == "2AD9" { resolve(.failure(error)); failure(error, role: role) }
        }
    }
}

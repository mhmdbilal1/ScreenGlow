import AppKit
import CoreAudio
import CoreBluetooth
import CoreGraphics
import Foundation
import ScreenCaptureKit
import SwiftUI

enum GlowMode: String, CaseIterable, Identifiable {
    case screen = "Screen Sync"
    case ambient = "Ambient"
    case solid = "Solid Color"
    var id: String { rawValue }
    var symbol: String {
        switch self { case .screen: "viewfinder"; case .ambient: "sparkles.tv"; case .solid: "circle.lefthalf.filled" }
    }
}

struct RGBColor: Equatable {
    var r: UInt8; var g: UInt8; var b: UInt8
    var swiftUIColor: Color { Color(.sRGB, red: Double(r)/255, green: Double(g)/255, blue: Double(b)/255, opacity: 1) }
    var hex: String { String(format: "#%02X%02X%02X", r, g, b) }
    static let violet = RGBColor(r: 125, g: 91, b: 255)
}

@MainActor
final class GlowModel: NSObject, ObservableObject {
    @Published var mode: GlowMode = .screen
    @Published var isSyncing = false
    @Published var isOn = false
    @Published var isConnected = false
    @Published var isScanning = false
    @Published var deviceName = "No strip connected"
    @Published var status = "Ready when you are"
    @Published var bleStatus = "Not connected"
    @Published var currentColor = RGBColor.violet
    @Published var smartBulbColor = RGBColor.violet
    @Published var bassBeat = 0.0
    @Published var bassBeatSequence = 0
    @Published var brightness = 82.0
    @Published var smoothness = 5.0
    @Published var dimDarkScenes = true
    @Published var selectedPreset = "Cinema"
    @Published var errorMessage: String?

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var pendingFrames: [[UInt8]] = []
    private var waitingForWriteAcknowledgement = false
    private var noResponseWriteBlocked = false
    private var capture: ScreenSampler?
    private var lastWrite = Date.distantPast
    private var previousRGB: RGBColor = .violet
    private var ambientTask: Task<Void, Never>?
    private var darkSceneTask: Task<Void, Never>?
    private var brightSceneTask: Task<Void, Never>?
    private var ambientHue = 0.73
    private let serviceID = CBUUID(string: "FFF0")
    private let characteristicID = CBUUID(string: "FFF3")

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func connect() {
        guard central.state == .poweredOn else {
            status = "Turn on Bluetooth to find your strip"
            if central.state == .unauthorized { errorMessage = "Allow Bluetooth access for ScreenGlow in System Settings." }
            return
        }
        isScanning = true
        status = "Looking for nearby Lotus Lantern strips…"
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        Task { try? await Task.sleep(for: .seconds(12)); if isScanning { central.stopScan(); isScanning = false; if !isConnected { status = "No strip found · Move closer and try again" } } }
    }

    func disconnect() {
        if let peripheral { central.cancelPeripheralConnection(peripheral) }
        isConnected = false; deviceName = "No strip connected"; status = "Disconnected"
    }

    func togglePower() {
        isOn.toggle()
        if isConnected { sendPower(isOn) }
    }

    func setMode(_ newMode: GlowMode) {
        mode = newMode
        if newMode == .screen { ambientTask?.cancel(); startSync() }
        else if newMode == .ambient { stopSync(); startAmbient() }
        else { ambientTask?.cancel(); stopSync() }
    }

    func startSync() {
        Task {
            do {
                if !CGPreflightScreenCaptureAccess(), !CGRequestScreenCaptureAccess() {
                    throw CaptureError.screenAccessDenied
                }
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let display = content.displays.first else { throw CaptureError.noDisplay }
                let ownApp = content.applications.first { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
                let filter = SCContentFilter(display: display, excludingApplications: ownApp.map { [$0] } ?? [], exceptingWindows: [])
                let sampler = ScreenSampler(
                    onColor: { [weak self] color in Task { @MainActor in self?.receive(color) } },
                    onBeat: { [weak self] strength in Task { @MainActor in
                        self?.bassBeat = strength
                        self?.bassBeatSequence &+= 1
                    } }
                )
                try await sampler.start(filter: filter)
                capture = sampler; isSyncing = true; status = "Matching the colors on your display"
                mode = .screen
            } catch {
                status = "Screen capture needs permission"
                errorMessage = "Screen capture could not start: \(error.localizedDescription)\n\nIf macOS says access is denied, enable ScreenGlow in System Settings → Privacy & Security → Screen & System Audio Recording, then quit and reopen the app."
            }
        }
    }

    func stopSync() {
        isSyncing = false; capture?.stop(); capture = nil
        if mode == .screen { status = "Screen sync paused" }
    }

    private func startAmbient() {
        ambientTask?.cancel()
        status = "A slow ambient color wash"
        ambientTask = Task { @MainActor in
            while !Task.isCancelled {
                ambientHue = (ambientHue + 0.008) .truncatingRemainder(dividingBy: 1)
                let color = Self.color(hue: ambientHue, saturation: 0.76, brightness: 0.92)
                currentColor = color; previousRGB = color
                if isOn, Date().timeIntervalSince(lastWrite) > 0.5 { lastWrite = Date(); sendColor(color) }
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    private static func color(hue: Double, saturation: Double, brightness: Double) -> RGBColor {
        let c = brightness * saturation
        let x = c * (1 - abs((hue * 6).truncatingRemainder(dividingBy: 2) - 1))
        let m = brightness - c
        let rgb: (Double, Double, Double)
        switch Int(hue * 6) % 6 {
        case 0: rgb = (c, x, 0); case 1: rgb = (x, c, 0); case 2: rgb = (0, c, x)
        case 3: rgb = (0, x, c); case 4: rgb = (x, 0, c); default: rgb = (c, 0, x)
        }
        return RGBColor(r: UInt8((rgb.0 + m) * 255), g: UInt8((rgb.1 + m) * 255), b: UInt8((rgb.2 + m) * 255))
    }

    func choosePreset(_ preset: String) { selectedPreset = preset }

    private func receive(_ raw: RGBColor) {
        let r = Double(raw.r) / 255, g = Double(raw.g) / 255, b = Double(raw.b) / 255
        let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
        if dimDarkScenes && isOn && luminance < 0.025 {
            brightSceneTask?.cancel()
            if darkSceneTask == nil {
                darkSceneTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(1.2))
                    guard let self, !Task.isCancelled else { return }
                    self.darkSceneTask = nil
                    self.isOn = false
                    self.currentColor = RGBColor(r: 0, g: 0, b: 0)
                    self.previousRGB = self.currentColor
                    self.sendPower(false)
                }
            }
        } else if luminance >= 0.025 {
            darkSceneTask?.cancel(); darkSceneTask = nil
        }
        if dimDarkScenes && !isOn && luminance > 0.065 {
            brightSceneTask?.cancel()
            if brightSceneTask == nil {
                brightSceneTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .milliseconds(220))
                    guard let self, !Task.isCancelled else { return }
                    self.brightSceneTask = nil
                    self.isOn = true
                    self.previousRGB = RGBColor(r: 0, g: 0, b: 0)
                    self.sendPower(true)
                }
            }
        } else if luminance <= 0.065 {
            brightSceneTask?.cancel(); brightSceneTask = nil
        }
        let target: RGBColor
        if dimDarkScenes && luminance < 0.025 {
            target = RGBColor(r: 0, g: 0, b: 0)
        } else {
            let saturationBoost = selectedPreset == "Vivid" ? 1.55 : selectedPreset == "Subtle" ? 1.0 : 1.28
            let vivid = Self.adjustSaturation(raw, amount: saturationBoost)
            let level = dimDarkScenes ? min(1, max(0, (luminance - 0.025) / 0.175)) : 1
            target = RGBColor(r: UInt8(Double(vivid.r) * level), g: UInt8(Double(vivid.g) * level), b: UInt8(Double(vivid.b) * level))
        }
        smartBulbColor = target
        // Keep a short color ramp to hide BLE steps without leaving the scene behind.
        let blend = max(0.55, min(1, 1 - smoothness / 100))
        if dimDarkScenes && luminance < 0.025 {
            previousRGB = target; currentColor = target
            guard isOn, Date().timeIntervalSince(lastWrite) > 0.025 else { return }
            lastWrite = Date(); sendColor(target); return
        }
        let color = RGBColor(r: UInt8(Double(previousRGB.r) * (1-blend) + Double(target.r) * blend), g: UInt8(Double(previousRGB.g) * (1-blend) + Double(target.g) * blend), b: UInt8(Double(previousRGB.b) * (1-blend) + Double(target.b) * blend))
        previousRGB = color; currentColor = color
        guard isOn, Date().timeIntervalSince(lastWrite) > 0.025 else { return }
        lastWrite = Date(); sendColor(color)
    }

    private static func adjustSaturation(_ color: RGBColor, amount: Double) -> RGBColor {
        let r = Double(color.r) / 255, g = Double(color.g) / 255, b = Double(color.b) / 255
        let high = max(r, g, b), low = min(r, g, b), delta = high - low
        guard high > 0, delta > 0 else { return color }
        let saturation = min(1, delta / high * amount)
        let rawHue: Double
        if high == r { rawHue = ((g - b) / delta).truncatingRemainder(dividingBy: 6) / 6 }
        else if high == g { rawHue = ((b - r) / delta + 2) / 6 }
        else { rawHue = ((r - g) / delta + 4) / 6 }
        return Self.color(hue: (rawHue + 1).truncatingRemainder(dividingBy: 1), saturation: saturation, brightness: high)
    }

    private func sendColor(_ color: RGBColor) {
        send(frame: [0x7E,0x07,0x05,0x03,color.r,color.g,color.b,0x10,0xEF])
    }

    private func sendPower(_ on: Bool) {
        send(frame: [0x7E,0x04,0x04,on ? 0x01 : 0x00,0x00,on ? 0x01 : 0x00,0xFF,0x00,0xEF])
    }

    private func send(frame: [UInt8]) {
        guard let peripheral, let characteristic = writeCharacteristic else {
            bleStatus = "No writable strip characteristic is ready"
            return
        }
        pendingFrames.append(frame)
        bleStatus = "Sending \(frame[2] == 0x05 ? "color" : frame[2] == 0x04 ? "power" : "brightness") command…"
        pumpWrites(peripheral, characteristic: characteristic)
    }

    private func pumpWrites(_ peripheral: CBPeripheral, characteristic: CBCharacteristic) {
        let supportsResponse = characteristic.properties.contains(.write)
        let supportsNoResponse = characteristic.properties.contains(.writeWithoutResponse)
        guard supportsResponse || supportsNoResponse else {
            bleStatus = "FFF3 does not support Bluetooth writes"
            return
        }

        if !supportsNoResponse && supportsResponse {
            guard !waitingForWriteAcknowledgement, let frame = pendingFrames.first else { return }
            pendingFrames.removeFirst()
            waitingForWriteAcknowledgement = true
            peripheral.writeValue(Data(wireFrame(frame)), for: characteristic, type: .withResponse)
            return
        }

        while !pendingFrames.isEmpty {
            guard peripheral.canSendWriteWithoutResponse else { noResponseWriteBlocked = true; return }
            let frame = pendingFrames.removeFirst()
            peripheral.writeValue(Data(wireFrame(frame)), for: characteristic, type: .withoutResponse)
        }
        noResponseWriteBlocked = false
    }

    private func wireFrame(_ frame: [UInt8]) -> [UInt8] {
        guard deviceName.contains("ELK-*"), frame.count == 9, [0x01, 0x03, 0x04].contains(frame[2]) else { return frame }
        let key: [UInt8] = [0x2A,0x7F,0xC1,0x94,0x33,0xDE,0x45,0xE0,0x8B,0x11,0x5C,0xA6,0x09,0xF2,0x7D,0xB8]
        var rng = SystemRandomNumberGenerator()
        let random = (0..<12).map { _ in UInt8.random(in: 0...255, using: &rng) }
        var plain = frame; plain[0] = 0xAA; plain[8] = 0x55
        var encrypted = [UInt8](repeating: 0, count: 21)
        for i in 0..<9 {
            let mask = ((Int(random[i]) * 27) & 0xff) ^ ((Int(random[(i+3) % 12]) + 55) & 0xff) ^ (Int(random[(i+7) % 12]) >> 2) ^ ((i * 85) & 0xff)
            encrypted[i] = plain[i] ^ UInt8(mask)
        }
        for i in 0..<12 { encrypted[9+i] = random[i] ^ key[i] }
        return encrypted
    }

    private func setBrightnessValue(_ value: Double) {
        let amount = UInt8(max(0, min(100, Int(value.rounded()))))
        send(frame: [0x7E,0x04,0x01,amount,0xFF,0xFF,0xFF,0x00,0xEF])
    }

    func updateBrightness(_ value: Double) { brightness = value; setBrightnessValue(value) }

    func sendQuickColor(_ color: RGBColor) {
        currentColor = color
        send(frame: [0x7E,0x07,0x05,0x03,color.r,color.g,color.b,0x10,0xEF])
    }

    private enum CaptureError: LocalizedError {
        case noDisplay
        case screenAccessDenied
        var errorDescription: String? {
            switch self {
            case .noDisplay: "No display is available for capture."
            case .screenAccessDenied: "macOS has not granted Screen Recording access to ScreenGlow yet."
            }
        }
    }
}

extension GlowModel: CBCentralManagerDelegate, CBPeripheralDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            switch central.state {
            case .poweredOn: self.status = "Bluetooth is ready"
            case .poweredOff: self.status = "Bluetooth is turned off"
            case .unauthorized: self.status = "Bluetooth permission is needed"
            default: self.status = "Connecting to Bluetooth…"
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name ?? ""
        guard ["ELK", "XSL-", "CLK-", "LED LIGHT STRIP"].contains(where: { name.uppercased().hasPrefix($0) }) else { return }
        Task { @MainActor in
            guard self.isScanning else { return }
            self.isScanning = false; central.stopScan(); self.peripheral = peripheral; self.deviceName = name
            self.status = "Connecting to \(name)…"; peripheral.delegate = self; central.connect(peripheral, options: nil)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in self.status = "Finding strip controls…"; self.bleStatus = "Bluetooth connected · checking FFF0/FFF3"; peripheral.discoverServices([self.serviceID]) }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in self.isConnected = false; self.status = "Couldn't connect · try again" }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in self.isConnected = false; self.writeCharacteristic = nil; self.status = "Strip disconnected" }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == CBUUID(string: "FFF0") }) else {
            Task { @MainActor in self.bleStatus = error?.localizedDescription ?? "Strip has no Lotus Lantern FFF0 service" }
            return
        }
        peripheral.discoverCharacteristics([CBUUID(string: "FFF3")], for: service)
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristic = service.characteristics?.first(where: { $0.uuid == CBUUID(string: "FFF3") }) else {
            Task { @MainActor in self.isConnected = false; self.bleStatus = error?.localizedDescription ?? "FFF3 color control was not found" }
            return
        }
        Task { @MainActor in
            self.writeCharacteristic = characteristic
            self.isConnected = true
            self.bleStatus = "FFF3 ready · \(characteristic.properties.contains(.write) ? "acknowledged writes" : "no-response writes")"
            self.isOn = true
            self.sendPower(true)
            self.updateBrightness(self.brightness); self.sendColor(self.currentColor)
            if self.mode == .screen { self.startSync() }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == CBUUID(string: "FFF3") else { return }
        Task { @MainActor in
            self.waitingForWriteAcknowledgement = false
            if let error { self.bleStatus = "Strip rejected command: \(error.localizedDescription)" }
            else { self.bleStatus = "Strip acknowledged command" }
            if let active = self.peripheral, let writeCharacteristic = self.writeCharacteristic {
                self.pumpWrites(active, characteristic: writeCharacteristic)
            }
        }
    }

    nonisolated func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        Task { @MainActor in
            guard let characteristic = self.writeCharacteristic, self.noResponseWriteBlocked else { return }
            self.pumpWrites(peripheral, characteristic: characteristic)
        }
    }
}

private final class ScreenSampler: NSObject, SCStreamOutput, SCStreamDelegate {
    private let onColor: (RGBColor) -> Void
    private let onBeat: (Double) -> Void
    private var stream: SCStream?
    private var lastSample = Date.distantPast
    private var lastBeat = Date.distantPast
    private var beatEnvelope = 0.0
    private var bassFilters: [Double] = []
    init(onColor: @escaping (RGBColor) -> Void, onBeat: @escaping (Double) -> Void) {
        self.onColor = onColor; self.onBeat = onBeat
    }

    func start(filter: SCContentFilter) async throws {
        let config = SCStreamConfiguration()
        config.width = 640; config.height = 360; config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.queueDepth = 2; config.pixelFormat = kCVPixelFormatType_32BGRA
        config.capturesAudio = true; config.sampleRate = 48_000; config.channelCount = 2
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: DispatchQueue(label: "ScreenGlow.samples", qos: .userInitiated))
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: DispatchQueue(label: "ScreenGlow.audio", qos: .userInitiated))
        try await stream.startCapture(); self.stream = stream
    }

    func stop() { guard let stream else { return }; Task { try? await stream.stopCapture() }; self.stream = nil }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        if type == .audio { sampleAudio(sampleBuffer); return }
        guard type == .screen, Date().timeIntervalSince(lastSample) > 0.016,
              let pixel = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastSample = Date(); CVPixelBufferLockBaseAddress(pixel, .readOnly); defer { CVPixelBufferUnlockBaseAddress(pixel, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixel) else { return }
        let width = CVPixelBufferGetWidth(pixel), height = CVPixelBufferGetHeight(pixel), row = CVPixelBufferGetBytesPerRow(pixel)
        let ptr = base.assumingMemoryBound(to: UInt8.self)
        var r = 0.0, g = 0.0, b = 0.0, count = 0.0
        // Center-weight the samples to favor the video content over window chrome.
        for y in stride(from: height / 8, to: height * 7 / 8, by: 4) {
            for x in stride(from: width / 8, to: width * 7 / 8, by: 4) {
                let i = y * row + x * 4
                b += Double(ptr[i]); g += Double(ptr[i+1]); r += Double(ptr[i+2]); count += 1
            }
        }
        guard count > 0 else { return }
        onColor(RGBColor(r: UInt8(r/count), g: UInt8(g/count), b: UInt8(b/count)))
    }

    private func sampleAudio(_ sampleBuffer: CMSampleBuffer) {
        guard let format = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee,
              asbd.mBitsPerChannel == 32,
              let buffers = try? sampleBuffer.withAudioBufferList(body: { list, _ in
                  var bassSum = 0.0
                  var count = 0.0
                  let isFloat = (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0
                  let sampleRate = max(8_000, asbd.mSampleRate)
                  let bassAlpha = (2 * Double.pi * 140 / sampleRate) / (1 + 2 * Double.pi * 140 / sampleRate)
                  if bassFilters.count < list.count { bassFilters += Array(repeating: 0, count: list.count - bassFilters.count) }
                  for (channel, buffer) in list.enumerated() {
                      guard let data = buffer.mData else { continue }
                      let samples = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
                      var bass = bassFilters[channel]
                      for i in 0..<samples {
                          let value: Double
                          if isFloat {
                              value = Double(data.assumingMemoryBound(to: Float.self)[i])
                          } else {
                              value = Double(data.assumingMemoryBound(to: Int32.self)[i]) / Double(Int32.max)
                          }
                          bass += bassAlpha * (value - bass)
                          bassSum += bass * bass
                          count += 1
                      }
                      bassFilters[channel] = bass
                  }
                  return count > 0 ? sqrt(bassSum / count) : 0.0
              }) else { return }

        let energy = buffers
        let baseline = beatEnvelope
        beatEnvelope = baseline * 0.985 + energy * 0.015
        let now = Date()
        if energy > 0.004, energy > max(0.0035, baseline * 1.13), now.timeIntervalSince(lastBeat) > 0.18 {
            lastBeat = now
            onBeat(min(1, max(0.1, energy / 0.10)))
        }
    }
    func stream(_ stream: SCStream, didStopWithError error: Error) { }
}

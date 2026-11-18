import Combine
import Foundation

struct MatterBulb: Identifiable, Equatable {
    let id: UInt64
    let name: String
}

@MainActor
final class MatterBridge: ObservableObject {
    @Published var bulbs: [MatterBulb] = []
    @Published var pairingCode = ""
    @Published var status = "Matter controller is running on this Mac"
    @Published var isConnected = false
    @Published var syncing = false
    @Published var bassSyncing = false
    @Published var syncBrightness = 60.0
    private var socket: URLSessionWebSocketTask?
    private var responseTask: Task<Void, Never>?
    private var messageID = 0
    private var busy = false
    private var pendingCommands: [String: CheckedContinuation<Any, Error>] = [:]
    private var beatTask: Task<Void, Never>?
    private var lastBeat = Date.distantPast
    private var darkScene: Bool?
    private var pendingColor: (Int, Int)?
    private var colorPump: Task<Void, Never>?
    private var pendingBrightnessLevel: Int?
    private var brightnessPump: Task<Void, Never>?
    private var currentCommandedLevel: Int?

    func connect() {
        guard !isConnected else { Task { await refresh() }; return }
        guard let url = URL(string: "ws://127.0.0.1:5580/ws") else { return }
        let ws = URLSession.shared.webSocketTask(with: url); socket = ws; ws.resume()
        Task {
            do {
                _ = try await ws.receive()
                isConnected = true
                responseTask = Task { @MainActor [weak self] in await self?.receiveResponses() }
                _ = try await command("start_listening")
                await refresh()
                status = "Connected to this Mac’s Matter controller"
            } catch { isConnected = false; status = "Matter controller isn’t responding" }
        }
    }

    func commission() {
        let code = pairingCode.filter(\.isNumber)
        guard code.count == 11 || pairingCode.hasPrefix("MT:") else { status = "Enter the temporary Matter code from Apple Home"; return }
        guard isConnected, !busy else { status = "Connect to the Matter controller first"; return }
        busy = true; status = "Adding the bulb to ScreenGlow…"
        Task {
            defer { busy = false }
            do {
                let codeToUse = pairingCode.hasPrefix("MT:") ? pairingCode : code
                _ = try await command("commission_with_code", args: ["code": codeToUse, "network_only": true, "discovery_timeout_s": 90])
                pairingCode = ""
                await refresh()
                status = "Bulb added · it remains in Apple Home"
            } catch { status = "Couldn’t add that bulb. Recheck its Apple Home sharing code and try again." }
        }
    }

    func refresh() async {
        guard isConnected else { connect(); return }
        do {
            let result = try await command("get_nodes", args: ["only_available": false])
            let values = result as? [[String: Any]] ?? []
            bulbs = values.compactMap { node in
                guard let raw = node["node_id"] as? NSNumber else { return nil }
                let attrs = node["attributes"] as? [String: Any] ?? [:]
                let label = attrs["0/40/5"] as? String
                let product = attrs["0/40/3"] as? String
                let name = label?.isEmpty == false ? label! : "\(product ?? "Cync bulb") · \(raw.uint64Value)"
                return MatterBulb(id: raw.uint64Value, name: name)
            }
        } catch { status = "Couldn’t read paired Matter devices" }
    }

    func power(_ on: Bool, bulb: MatterBulb) {
        Task { _ = try? await command("device_command", args: ["node_id": bulb.id, "endpoint_id": 1, "cluster_id": 6, "command_name": on ? "on" : "off", "payload": [:]]) }
    }

    func screenColor(_ color: RGBColor) {
        guard syncing, isConnected else { return }
        let isDark = max(color.r, color.g, color.b) < 5
        if darkScene != isDark {
            darkScene = isDark
            if isDark {
                stopBassPulse(restore: false)
                currentCommandedLevel = nil
            }
            for bulb in bulbs { power(!isDark, bulb: bulb) }
            if !isDark { applySyncBrightness() }
        }
        guard !isDark else { return }
        pendingColor = Self.xy(color)
        guard colorPump == nil else { return }
        colorPump = Task { @MainActor in
            while self.syncing, let (x, y) = self.pendingColor {
                self.pendingColor = nil
                await self.setColor(x: x, y: y)
            }
            self.colorPump = nil
        }
    }

    func bassBeat(_ strength: Double) {
        guard syncing, bassSyncing, isConnected, darkScene != true,
              Date().timeIntervalSince(lastBeat) > 0.18 else { return }
        lastBeat = Date()
        beatTask?.cancel()
        let normalLevel = currentLevel
        let dipFraction = 0.30 - min(1, max(0, strength)) * 0.12
        let pulseLevel = max(1, Int(Double(normalLevel) * dipFraction))
        currentCommandedLevel = normalLevel
        beatTask = Task { @MainActor in
            await self.setLevel(pulseLevel)
            guard !Task.isCancelled else { return }
            try? await Task.sleep(for: .milliseconds(95))
            guard !Task.isCancelled else { return }
            await self.setLevel(normalLevel)
        }
    }

    func applySyncBrightness() {
        guard syncing, isConnected, darkScene != true else { return }
        let level = currentLevel
        guard currentCommandedLevel != level else { return }
        currentCommandedLevel = level
        stopBassPulse(restore: false)
        pendingBrightnessLevel = level
        guard brightnessPump == nil else { return }
        brightnessPump = Task { @MainActor in
            while let nextLevel = self.pendingBrightnessLevel {
                self.pendingBrightnessLevel = nil
                await self.setLevel(nextLevel)
            }
            self.brightnessPump = nil
        }
    }

    func stopBassPulse(restore: Bool = true) {
        beatTask?.cancel(); beatTask = nil
        guard restore, syncing, isConnected, darkScene != true else { return }
        let level = currentLevel
        currentCommandedLevel = level
        Task { await self.setLevel(level) }
    }

    private var currentLevel: Int {
        Int((syncBrightness / 100 * 254).rounded())
    }

    private func setLevel(_ level: Int) async {
        await withTaskGroup(of: Void.self) { group in
            for bulb in bulbs {
                group.addTask {
                    _ = try? await self.command("device_command", args: ["node_id": bulb.id, "endpoint_id": 1, "cluster_id": 8, "command_name": "moveToLevelWithOnOff", "payload": ["level": level, "transitionTime": 0, "optionsMask": 0, "optionsOverride": 0]])
                }
            }
            await group.waitForAll()
        }
    }

    private func setColor(x: Int, y: Int) async {
        await withTaskGroup(of: Void.self) { group in
            for bulb in bulbs {
                group.addTask {
                    _ = try? await self.command("device_command", args: ["node_id": bulb.id, "endpoint_id": 1, "cluster_id": 768, "command_name": "moveToColor", "payload": ["colorX": x, "colorY": y, "transitionTime": 0, "optionsMask": 0, "optionsOverride": 0]])
                }
            }
            await group.waitForAll()
        }
    }

    private func command(_ name: String, args: [String: Any] = [:]) async throws -> Any {
        guard let socket else { throw URLError(.notConnectedToInternet) }
        messageID += 1; let id = String(messageID)
        let data = try JSONSerialization.data(withJSONObject: ["message_id": id, "command": name, "args": args])
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Any, Error>) in
            pendingCommands[id] = continuation
            Task { @MainActor in
                do { try await socket.send(.data(data)) }
                catch {
                    if let pending = self.pendingCommands.removeValue(forKey: id) {
                        pending.resume(throwing: error)
                    }
                }
            }
        }
    }

    private func receiveResponses() async {
        while isConnected, !Task.isCancelled, let socket {
            do {
                let message = try await socket.receive()
                let bytes: Data
                switch message { case .data(let data): bytes = data; case .string(let string): bytes = Data(string.utf8); @unknown default: continue }
                guard let response = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
                      let id = response["message_id"] as? String,
                      let continuation = pendingCommands.removeValue(forKey: id) else { continue }
                if response["error_code"] != nil { continuation.resume(throwing: URLError(.cannotParseResponse)) }
                else { continuation.resume(returning: response["result"] ?? NSNull()) }
            } catch {
                isConnected = false
                status = "Matter controller connection was interrupted"
                let pending = Array(pendingCommands.values)
                pendingCommands.removeAll()
                for continuation in pending { continuation.resume(throwing: error) }
                break
            }
        }
    }

    private static func xy(_ c: RGBColor) -> (Int, Int) {
        let rgb = [Double(c.r), Double(c.g), Double(c.b)].map { v -> Double in let n = v / 255; return n <= 0.04045 ? n / 12.92 : pow((n + 0.055) / 1.055, 2.4) }
        let X = rgb[0] * 0.664511 + rgb[1] * 0.154324 + rgb[2] * 0.162028
        let Y = rgb[0] * 0.283881 + rgb[1] * 0.668433 + rgb[2] * 0.047685
        let Z = rgb[0] * 0.000088 + rgb[1] * 0.072310 + rgb[2] * 0.986039
        let sum = X + Y + Z
        guard sum > 0 else { return (0, 0) }
        return (Int(max(0, min(65535, X / sum * 65535))), Int(max(0, min(65535, Y / sum * 65535))))
    }
}

import SwiftUI

private enum Palette {
    static let ink = Color(red: 0.10, green: 0.16, blue: 0.24)
    static let background = Color(red: 0.79, green: 0.88, blue: 0.98)
    static let panel = Color.white.opacity(0.88)
    static let raised = Color(red: 0.13, green: 0.14, blue: 0.19)
    static let muted = Color(red: 0.24, green: 0.32, blue: 0.42)
    static let accent = Color(red: 0.18, green: 0.48, blue: 0.87)
}

struct MainWindow: View {
    @ObservedObject var model: GlowModel
    @StateObject private var matter = MatterBridge()
    @State private var activeSection = "Overview"
    @State private var showPermissionInfo = false

    var body: some View {
        GeometryReader { proxy in
            Group {
                if proxy.size.width < 760 {
                    VStack(spacing: 0) { compactNavigation; titleBar; pageContent }
                } else {
                    HStack(spacing: 0) { sidebar; Rectangle().fill(Palette.ink.opacity(0.1)).frame(width: 1); VStack(spacing: 0) { titleBar; pageContent } }
                }
            }
        }
        .background(LinearGradient(colors: [Color(red: 0.26, green: 0.57, blue: 0.91), Color(red: 0.66, green: 0.82, blue: 0.97), Color(red: 0.96, green: 0.98, blue: 1)], startPoint: .top, endPoint: .bottom))
        .alert("ScreenGlow", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("Got it", role: .cancel) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
        .preferredColorScheme(.light)
        .onChange(of: model.smartBulbColor) { _, color in matter.screenColor(color) }
        .onChange(of: model.bassBeatSequence) { _, _ in matter.bassBeat(model.bassBeat) }
        .onChange(of: matter.syncBrightness) { _, _ in matter.applySyncBrightness() }
        .onChange(of: matter.syncing) { _, active in
            if active { matter.applySyncBrightness() } else { matter.stopBassPulse() }
        }
        .onChange(of: matter.bassSyncing) { _, active in
            if !active { matter.stopBassPulse() }
        }
    }

    private var pageContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 25) {
                if activeSection == "Devices" { bottomCards; sectionHeading("DEVICE STATUS", note: model.bleStatus) }
                else if activeSection == "Cync Bulbs" { cyncPanel }
                else { hero; controls; if activeSection == "Overview" { bottomCards } }
            }.padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 30).frame(maxWidth: 1120, alignment: .leading).frame(maxWidth: .infinity)
        }
    }

    private var compactNavigation: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) { navItem("Overview", symbol: "square.grid.2x2.fill"); navItem("Lighting", symbol: "lightbulb.max.fill"); navItem("Devices", symbol: "dot.radiowaves.left.and.right"); navItem("Cync Bulbs", symbol: "lightbulb.2.fill") }.padding(.horizontal, 6).padding(.vertical, 7)
        }.background(Color.white.opacity(0.7))
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(LinearGradient(colors: [Palette.accent, Color(red: 0.29, green: 0.67, blue: 1)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Image(systemName: "light.beacon.max.fill").font(.system(size: 18, weight: .semibold)).foregroundStyle(Palette.ink)
                }.frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 1) {
                    Text("ScreenGlow").font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(Palette.ink)
                    Text("LIGHTING STUDIO").font(.system(size: 9, weight: .bold, design: .rounded)).tracking(1.1).foregroundStyle(Palette.muted)
                }
            }.padding(.horizontal, 19).padding(.top, 30).padding(.bottom, 35)

            Text("WORKSPACE").font(.system(size: 10, weight: .bold)).tracking(1.1).foregroundStyle(Palette.muted.opacity(0.8)).padding(.horizontal, 20).padding(.bottom, 10)
            navItem("Overview", symbol: "square.grid.2x2.fill")
            navItem("Lighting", symbol: "lightbulb.max.fill")
            navItem("Devices", symbol: "dot.radiowaves.left.and.right")
            navItem("Cync Bulbs", symbol: "lightbulb.2.fill")

            Spacer()
            HStack(spacing: 10) {
                Circle().fill(model.isConnected ? Color.green : Color.orange).frame(width: 8, height: 8).shadow(color: (model.isConnected ? Color.green : Color.orange).opacity(0.6), radius: 5)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.isConnected ? "Strip connected" : "Strip not connected").font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.ink)
                    Text(model.status).font(.system(size: 10)).foregroundStyle(Palette.muted).lineLimit(1)
                }
            }.padding(13).frame(maxWidth: .infinity, alignment: .leading).background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 12)).padding(.horizontal, 14).padding(.bottom, 19)
        }
        .frame(width: 200).background(Color.white.opacity(0.7))
    }

    private var cyncPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionHeading("CYNC BULBS", note: "Matter control for the bulbs already in Apple Home")
            VStack(alignment: .leading, spacing: 12) {
                Text("CONNECT APPLE HOME TO SCREEN GLOW").font(.system(size: 10, weight: .bold)).tracking(1).foregroundStyle(Palette.ink)
                Text("Keep the bulbs in Apple Home and share them to this Mac over Matter. In Apple Home, open a bulb’s settings, choose Turn On Pairing Mode, and copy its temporary code. Paste the code below. ScreenGlow adds the bulb as a second controller, so it stays in Apple Home too.")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                SecureField("Temporary Apple Home Matter code", text: $matter.pairingCode).textFieldStyle(.roundedBorder)
                HStack {
                    Button(matter.isConnected ? "Matter controller ready" : "Connect to this Mac") { matter.connect() }.buttonStyle(.borderedProminent).tint(Palette.accent)
                    Button("Add bulb") { matter.commission() }.buttonStyle(.bordered).disabled(!matter.isConnected)
                    Spacer(minLength: 4)
                    Button(matter.syncing ? "Stop sync" : "Screen sync") { matter.syncing.toggle(); if matter.syncing { model.startSync() } else { model.stopSync() } }.buttonStyle(.bordered).disabled(matter.bulbs.isEmpty)
                }
                Toggle("Bass sync", isOn: $matter.bassSyncing)
                    .font(.system(size: 11, weight: .medium)).tint(Palette.accent)
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text("Screen sync brightness").font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.ink)
                        Spacer()
                        Text("\(Int(matter.syncBrightness))%")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(Palette.muted)
                    }
                    Slider(value: $matter.syncBrightness, in: 5...100).tint(Palette.accent).controlSize(.small)
                }
                Text(matter.status).font(.system(size: 11)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            }.padding(18).background(Palette.panel, in: RoundedRectangle(cornerRadius: 15))

            if !matter.bulbs.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    sectionHeading("COLOR PALETTE", note: "A color for every connected bulb")
                    HStack(spacing: 12) {
                        ForEach([Color(red: 0.98, green: 0.25, blue: 0.34), Color(red: 1, green: 0.54, blue: 0.18), Color(red: 1, green: 0.82, blue: 0.24), Color(red: 0.22, green: 0.78, blue: 0.49), Color(red: 0.12, green: 0.68, blue: 0.87), Color(red: 0.25, green: 0.43, blue: 0.98), Color(red: 0.63, green: 0.35, blue: 0.94), Color.white], id: \.self) { color in
                            Button { if let rgb = color.rgbColor { matter.screenColor(rgb); if let color = color.rgbColor { model.currentColor = color } } } label: { Circle().fill(color).frame(width: 30, height: 30).overlay(Circle().stroke(.white, lineWidth: 2)).shadow(color: color.opacity(0.25), radius: 5, y: 2) }.buttonStyle(.plain)
                        }
                    }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(Palette.panel, in: RoundedRectangle(cornerRadius: 15))
                }
                VStack(alignment: .leading, spacing: 12) {
                    sectionHeading("AVAILABLE LIGHTS", note: "Choose which bulbs follow the screen")
                    ForEach(matter.bulbs) { bulb in
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 12) {
                                Image(systemName: "lightbulb.max.fill").foregroundStyle(Palette.accent)
                                Text(bulb.name).font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.ink)
                                Spacer()
                                Button("Turn off") { matter.power(false, bulb: bulb) }.buttonStyle(.bordered)
                                Button("Turn on") { matter.power(true, bulb: bulb) }.buttonStyle(.bordered)
                            }.padding(13).background(Palette.panel, in: RoundedRectangle(cornerRadius: 12))
                            VStack(alignment: .leading, spacing: 10) {
                                HStack { Image(systemName: "lightbulb.max.fill"); Text(bulb.name) }
                                HStack { Button("Turn off") { matter.power(false, bulb: bulb) }.buttonStyle(.bordered); Button("Turn on") { matter.power(true, bulb: bulb) }.buttonStyle(.bordered) }
                            }.padding(13).background(Palette.panel, in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
            }
        }
    }

    private func navItem(_ title: String, symbol: String) -> some View {
        Button { activeSection = title } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.system(size: 15, weight: .medium)).frame(width: 20)
                Text(title).font(.system(size: 13, weight: activeSection == title ? .semibold : .medium))
                Spacer()
                if title == "Devices" && model.isConnected { Circle().fill(Color.green).frame(width: 6, height: 6) }
            }
            .foregroundStyle(activeSection == title ? .white : Palette.muted)
            .padding(.horizontal, 13).frame(height: 40)
            .background(activeSection == title ? Palette.accent.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 9))
            .overlay(alignment: .leading) { if activeSection == title { RoundedRectangle(cornerRadius: 2).fill(Palette.accent).frame(width: 3, height: 20) } }
            .contentShape(Rectangle())
        }.buttonStyle(.plain).padding(.horizontal, 11).padding(.bottom, 3)
    }

    private var titleBar: some View {
        HStack {
            HStack(spacing: 8) {
                Text("Lighting").foregroundStyle(Palette.muted)
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(Palette.muted.opacity(0.6))
                Text(activeSection).foregroundStyle(Palette.ink)
            }.font(.system(size: 12, weight: .medium))
            Spacer()
            Button { showPermissionInfo = true; model.errorMessage = "ScreenGlow uses Apple's screen capture permission to sample the colors shown on your display. Captured frames stay on your Mac and are never saved." } label: {
                Image(systemName: "questionmark.circle").font(.system(size: 16)).foregroundStyle(Palette.muted)
            }.buttonStyle(.plain).help("About ScreenGlow")
            Circle().fill(LinearGradient(colors: [Palette.accent, Color.cyan], startPoint: .topLeading, endPoint: .bottomTrailing)).frame(width: 27, height: 27).overlay(Text("B").font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.ink)).padding(.leading, 7)
        }
        .padding(.horizontal, 27).frame(height: 62)
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.ink.opacity(0.1)).frame(height: 1) }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Your screen, in a new light.").font(.system(size: 27, weight: .bold, design: .rounded)).foregroundStyle(Palette.ink)
                    Text("Let your Lotus Lantern strip follow the colors on your Mac.").font(.system(size: 13)).foregroundStyle(Palette.muted)
                }
                Spacer(minLength: 12)
                Button { model.togglePower() } label: {
                    HStack(spacing: 8) { Image(systemName: "power").font(.system(size: 12, weight: .bold)); Text(model.isOn ? "Lights on" : "Lights off").font(.system(size: 12, weight: .semibold)) }
                        .foregroundStyle(model.isOn ? .white : Palette.muted).padding(.horizontal, 14).frame(height: 36)
                        .background(model.isOn ? Palette.accent.opacity(0.22) : .white.opacity(0.07), in: Capsule())
                        .overlay(Capsule().stroke(model.isOn ? Palette.accent.opacity(0.42) : .white.opacity(0.1), lineWidth: 1))
                }.buttonStyle(.plain).disabled(!model.isConnected).opacity(model.isConnected ? 1 : 0.5)
            }
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 18).fill(LinearGradient(colors: [model.currentColor.swiftUIColor.opacity(0.45), Color(red: 0.12, green: 0.11, blue: 0.2), Color(red: 0.1, green: 0.13, blue: 0.22)], startPoint: .topLeading, endPoint: .bottomTrailing))
                RoundedRectangle(cornerRadius: 18).fill(.ultraThinMaterial.opacity(0.28))
                HStack(alignment: .center, spacing: 25) {
                    previewScreen
                        .frame(maxWidth: .infinity)
                    VStack(alignment: .leading, spacing: 15) {
                        HStack(spacing: 7) {
                            Circle().fill(model.isSyncing ? Color.green : Color.white.opacity(0.35)).frame(width: 7, height: 7)
                            Text(model.isSyncing ? "LIVE COLOR MATCHING" : "AMBIENT PREVIEW").font(.system(size: 9, weight: .bold)).tracking(1.1).foregroundStyle(Palette.ink)
                        }
                        Text(model.currentColor.hex).font(.system(size: 28, weight: .semibold, design: .rounded)).foregroundStyle(Palette.ink)
                        Text(model.isSyncing ? "Sampling your display" : "Connect your strip to begin").font(.system(size: 12)).foregroundStyle(Palette.ink)
                        Button {
                            if model.isSyncing { model.stopSync() } else { model.startSync() }
                        } label: {
                            HStack(spacing: 8) { Image(systemName: model.isSyncing ? "pause.fill" : "play.fill"); Text(model.isSyncing ? "Pause sync" : "Start screen sync") }
                                .font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.ink).padding(.horizontal, 14).frame(height: 37)
                                .background(Palette.accent, in: RoundedRectangle(cornerRadius: 10))
                        }.buttonStyle(.plain).disabled(!model.isConnected).opacity(model.isConnected ? 1 : 0.55)
                    }.frame(width: 220, alignment: .leading).padding(.trailing, 23)
                }.padding(.horizontal, 27).padding(.vertical, 22)
                RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.12), lineWidth: 1)
            }
            .frame(height: 225).clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay { RoundedRectangle(cornerRadius: 18).fill(model.currentColor.swiftUIColor.opacity(0.05)).allowsHitTesting(false) }
            .shadow(color: model.currentColor.swiftUIColor.opacity(0.15), radius: 35, y: 12)
        }
    }

    private var previewScreen: some View {
        VStack(spacing: 0) {
            HStack(spacing: 5) { Circle().fill(Color(red: 1, green: 0.36, blue: 0.34)); Circle().fill(Color(red: 1, green: 0.75, blue: 0.28)); Circle().fill(Color(red: 0.22, green: 0.81, blue: 0.39)); Spacer(); Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 8)).foregroundStyle(.white.opacity(0.45)) }.frame(height: 18).padding(.horizontal, 10).background(.black.opacity(0.42))
            ZStack {
                LinearGradient(colors: [Color(red: 0.11, green: 0.2, blue: 0.47), Color(red: 0.45, green: 0.19, blue: 0.43), Color(red: 0.93, green: 0.43, blue: 0.24)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle().fill(Color.orange.opacity(0.85)).frame(width: 49, height: 49).blur(radius: 2).offset(x: 74, y: -16)
                Ellipse().fill(Color.black.opacity(0.5)).frame(width: 270, height: 67).rotationEffect(.degrees(-8)).offset(x: -10, y: 53)
                Image(systemName: "play.fill").font(.system(size: 17)).foregroundStyle(Palette.ink).padding(15).background(.black.opacity(0.3), in: Circle()).overlay(Circle().stroke(.white.opacity(0.65), lineWidth: 1)).shadow(color: .black.opacity(0.25), radius: 10)
                VStack { Spacer(); HStack(spacing: 6) { Image(systemName: "film"); Text("DISPLAY PREVIEW") }.font(.system(size: 8, weight: .bold)).tracking(1).foregroundStyle(.white.opacity(0.68)).padding(.bottom, 9) }
            }.clipped()
        }
        .frame(maxWidth: .infinity).frame(height: 166)
        .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 11))
        .clipShape(RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(.white.opacity(0.14), lineWidth: 1))
    }

    private var controls: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 16) {
                sectionHeading("LIGHTING MODE", note: "Choose how your strip responds")
                HStack(spacing: 9) {
                    ForEach(GlowMode.allCases) { option in
                        Button { model.setMode(option) } label: {
                            VStack(alignment: .leading, spacing: 12) {
                                Image(systemName: option.symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(model.mode == option ? Palette.accent : Palette.muted)
                                Text(option.rawValue).font(.system(size: 10, weight: .semibold)).foregroundStyle(Palette.ink).lineLimit(1).minimumScaleFactor(0.75)
                                if option == .screen { Text("Screen reactive").font(.system(size: 9)).foregroundStyle(Palette.muted) }
                                else if option == .ambient { Text("Soft color flow").font(.system(size: 9)).foregroundStyle(Palette.muted) }
                                else { Text("One color").font(.system(size: 9)).foregroundStyle(Palette.muted) }
                            }
                            .frame(maxWidth: .infinity, minHeight: 87, alignment: .leading).padding(12)
                            .background(model.mode == option ? Palette.accent.opacity(0.14) : .white.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(model.mode == option ? Palette.accent.opacity(0.56) : .white.opacity(0.075), lineWidth: 1))
                        }.buttonStyle(.plain)
                    }
                }
                sectionHeading("COLOR TUNING", note: "Fine tune the look")
                HStack(spacing: 10) {
                    ForEach([("Cinema", Color(red: 0.49, green: 0.32, blue: 1)), ("Vivid", Color(red: 0.1, green: 0.77, blue: 1)), ("Subtle", Color(red: 0.98, green: 0.5, blue: 0.55))], id: \.0) { name, color in
                        Button { model.choosePreset(name) } label: {
                            HStack(spacing: 7) { Circle().fill(color).frame(width: 8, height: 8); Text(name).font(.system(size: 10, weight: .medium)) }
                                .foregroundStyle(model.selectedPreset == name ? Palette.accent : Palette.muted)
                                .padding(.horizontal, 11).frame(height: 28).background(model.selectedPreset == name ? .white.opacity(0.1) : .clear, in: Capsule())
                                .overlay(Capsule().stroke(.white.opacity(model.selectedPreset == name ? 0.16 : 0.07), lineWidth: 1))
                        }.buttonStyle(.plain)
                    }
                }
            }
            .padding(19).background(Palette.panel, in: RoundedRectangle(cornerRadius: 15)).overlay(RoundedRectangle(cornerRadius: 15).stroke(.white.opacity(0.065), lineWidth: 1))

            VStack(alignment: .leading, spacing: 18) {
                sectionHeading("OUTPUT", note: "Adjust your strip")
                VStack(spacing: 16) {
                    sliderRow(title: "Brightness", value: $model.brightness, icon: "sun.max.fill", range: 0...100) { model.updateBrightness($0) }
                    Rectangle().fill(Palette.ink.opacity(0.1)).frame(height: 1)
                    sliderRow(title: "Smoothness", value: $model.smoothness, icon: "waveform.path", range: 0...100) { _ in }
                }
                Toggle("Dim dark scenes", isOn: $model.dimDarkScenes)
                    .font(.system(size: 10, weight: .medium)).tint(Palette.accent)
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 4).fill(model.currentColor.swiftUIColor).frame(width: 26, height: 18).overlay(RoundedRectangle(cornerRadius: 4).stroke(.white.opacity(0.22), lineWidth: 1))
                    Text(model.currentColor.hex).font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(Palette.muted)
                    Spacer()
                    Text("LIVE").font(.system(size: 8, weight: .bold)).tracking(0.8).foregroundStyle(model.isSyncing ? Color.green : Palette.muted).padding(.horizontal, 7).padding(.vertical, 4).background(.white.opacity(0.05), in: Capsule())
                }.padding(.top, 1)
            }.padding(19).frame(maxWidth: 310).background(Palette.panel, in: RoundedRectangle(cornerRadius: 15)).overlay(RoundedRectangle(cornerRadius: 15).stroke(.white.opacity(0.065), lineWidth: 1))
        }
    }

    private var bottomCards: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 12) {
                HStack { sectionHeading("CONNECTED DEVICE", note: nil); Spacer(); Image(systemName: "ellipsis").foregroundStyle(Palette.muted) }
                HStack(spacing: 12) {
                    ZStack { RoundedRectangle(cornerRadius: 11).fill(LinearGradient(colors: [Palette.accent.opacity(0.3), Color.cyan.opacity(0.14)], startPoint: .topLeading, endPoint: .bottomTrailing)); Image(systemName: "light.strip.2.fill").font(.system(size: 19)).foregroundStyle(Color(red: 0.75, green: 0.66, blue: 1)) }.frame(width: 45, height: 45)
                    VStack(alignment: .leading, spacing: 4) { Text(model.isConnected ? model.deviceName : "Lotus Lantern Strip").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.ink); Text(model.isConnected ? "Bluetooth LE · Connected" : "Bluetooth LE · Not connected").font(.system(size: 10)).foregroundStyle(Palette.muted) }
                    Spacer()
                    Button { model.isConnected ? model.disconnect() : model.connect() } label: {
                        Text(model.isConnected ? "Disconnect" : (model.isScanning ? "Searching…" : "Connect"))
                            .font(.system(size: 10, weight: .semibold)).foregroundStyle(Palette.ink).padding(.horizontal, 12).frame(height: 30)
                            .background(model.isConnected ? .white.opacity(0.08) : Palette.accent, in: RoundedRectangle(cornerRadius: 8))
                    }.buttonStyle(.plain).disabled(model.isScanning && !model.isConnected)
                }
                Text(model.bleStatus).font(.system(size: 10)).foregroundStyle(model.bleStatus.contains("rejected") || model.bleStatus.contains("not found") ? Color.orange : Palette.muted).lineLimit(2)
            }.padding(17).frame(maxWidth: .infinity).background(Palette.panel, in: RoundedRectangle(cornerRadius: 15)).overlay(RoundedRectangle(cornerRadius: 15).stroke(.white.opacity(0.065), lineWidth: 1))

            VStack(alignment: .leading, spacing: 12) {
                sectionHeading("QUICK COLOR", note: "Tap to set a color")
                HStack(spacing: 9) {
                    ForEach([Color(red: 0.55, green: 0.3, blue: 1), Color(red: 0.18, green: 0.54, blue: 1), Color(red: 0.1, green: 0.82, blue: 0.67), Color(red: 1, green: 0.51, blue: 0.24), Color(red: 1, green: 0.3, blue: 0.52), Color.white], id: \.self) { color in
                        Button { if let rgb = color.rgbColor { model.currentColor = rgb; model.sendQuickColor(rgb) } } label: { Circle().fill(color).frame(width: 22, height: 22).overlay(Circle().stroke(.white.opacity(0.5), lineWidth: 1)) }.buttonStyle(.plain)
                    }
                    Spacer(minLength: 0)
                }.frame(height: 40)
            }.padding(17).frame(width: 300).background(Palette.panel, in: RoundedRectangle(cornerRadius: 15)).overlay(RoundedRectangle(cornerRadius: 15).stroke(.white.opacity(0.065), lineWidth: 1))
        }
    }

    private func sectionHeading(_ title: String, note: String?) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 10, weight: .bold)).tracking(1.0).foregroundStyle(Palette.ink)
            if let note { Text(note).font(.system(size: 10)).foregroundStyle(Palette.muted) }
        }
    }

    private func sliderRow(title: String, value: Binding<Double>, icon: String, range: ClosedRange<Double>, onChange: @escaping (Double) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Image(systemName: icon).font(.system(size: 10)).foregroundStyle(Palette.accent); Text(title).font(.system(size: 10, weight: .medium)).foregroundStyle(Palette.ink); Spacer(); Text("\(Int(value.wrappedValue))%").font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(Palette.muted) }
            Slider(value: value, in: range, onEditingChanged: { _ in onChange(value.wrappedValue) }).tint(Palette.accent).controlSize(.small)
        }
    }
}

private extension Color {
    var rgbColor: RGBColor? {
        let c = NSColor(self).usingColorSpace(.deviceRGB) ?? NSColor.white
        return RGBColor(r: UInt8(c.redComponent * 255), g: UInt8(c.greenComponent * 255), b: UInt8(c.blueComponent * 255))
    }
}

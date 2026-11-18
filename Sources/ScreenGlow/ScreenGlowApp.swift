import SwiftUI

@main
struct ScreenGlowApp: App {
    @StateObject private var model = GlowModel()

    var body: some Scene {
        WindowGroup {
            LaunchExperience(model: model)
                .frame(minWidth: 600, minHeight: 480)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) { }
            SidebarCommands()
        }
    }
}

private struct LaunchExperience: View {
    @ObservedObject var model: GlowModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingIntro = true
    @State private var glowOn = false

    var body: some View {
        ZStack {
            MainWindow(model: model)
            if showingIntro {
                ZStack {
                    LinearGradient(
                        colors: [Color(red: 0.10, green: 0.17, blue: 0.30), Color(red: 0.06, green: 0.08, blue: 0.15)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    VStack(spacing: 18) {
                        ZStack {
                            Circle()
                                .fill(Color.cyan.opacity(glowOn ? 0.25 : 0.10))
                                .frame(width: 112, height: 112)
                                .blur(radius: 22)
                            RoundedRectangle(cornerRadius: 25, style: .continuous)
                                .fill(LinearGradient(colors: [Color(red: 0.20, green: 0.60, blue: 1), Color(red: 0.47, green: 0.35, blue: 1)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 76, height: 76)
                                .shadow(color: Color.cyan.opacity(glowOn ? 0.50 : 0.18), radius: glowOn ? 22 : 10)
                            Image(systemName: "light.beacon.max.fill")
                                .font(.system(size: 34, weight: .medium))
                                .foregroundStyle(.white)
                                .rotationEffect(.degrees(glowOn ? 4 : -4))
                        }
                        VStack(spacing: 5) {
                            Text("ScreenGlow")
                                .font(.system(size: 22, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white)
                            Text("LIGHTING STUDIO")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .tracking(2.2)
                                .foregroundStyle(.white.opacity(0.62))
                        }
                        Capsule()
                            .fill(.white.opacity(0.14))
                            .frame(width: 42, height: 3)
                            .overlay(alignment: .leading) {
                                Capsule().fill(Color.cyan).frame(width: glowOn ? 42 : 16, height: 3)
                            }
                            .padding(.top, 4)
                    }
                }
                .transition(.opacity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("ScreenGlow")
                .onAppear {
                    guard !reduceMotion else {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                            withAnimation(.easeOut(duration: 0.25)) { showingIntro = false }
                        }
                        return
                    }
                    withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { glowOn = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.35) {
                        withAnimation(.easeOut(duration: 0.35)) { showingIntro = false }
                    }
                }
            }
        }
    }
}

// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ScreenGlow",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "ScreenGlow", targets: ["ScreenGlow"])],
    targets: [.executableTarget(name: "ScreenGlow", path: "Sources/ScreenGlow")],
    swiftLanguageModes: [.v5]
)

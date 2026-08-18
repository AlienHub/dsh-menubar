// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DSHMenuBar",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "DSHMenuBar", targets: ["DSHMenuBar"])],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.2")],
    targets: [.executableTarget(name: "DSHMenuBar", dependencies: [.product(name: "Sparkle", package: "Sparkle")])]
)

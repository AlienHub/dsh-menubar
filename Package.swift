// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DSHMenuBar",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "DSHMenuBar", targets: ["DSHMenuBar"])],
    targets: [.executableTarget(name: "DSHMenuBar")]
)

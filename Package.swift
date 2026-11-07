// swift-tools-version: 6.3
import PackageDescription
let package = Package(name: "Steadfast", platforms: [.macOS("26.0")], products: [.executable(name: "Steadfast", targets: ["SteadfastApp"]), .executable(name: "steadfastd", targets: ["SteadfastService"])], targets: [
 .target(name: "SteadfastCore"),
 .executableTarget(name: "SteadfastApp", dependencies: ["SteadfastCore"], swiftSettings: [.defaultIsolation(MainActor.self), .enableUpcomingFeature("NonisolatedNonsendingByDefault")]),
 .executableTarget(name: "SteadfastService", dependencies: ["SteadfastCore"], swiftSettings: [.defaultIsolation(MainActor.self), .enableUpcomingFeature("NonisolatedNonsendingByDefault")]),
 .testTarget(name: "SteadfastCoreTests", dependencies: ["SteadfastCore"])
])

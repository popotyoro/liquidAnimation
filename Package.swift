// swift-tools-version: 6.4
import PackageDescription

let concurrencySettings: [SwiftSetting] = [
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("MemberImportVisibility"),
]

let package = Package(
    name: "LiquidFluid",
    platforms: [.iOS("27.0")],
    products: [.library(name: "LiquidFluid", targets: ["LiquidFluid"])],
    targets: [
        .target(
            name: "LiquidFluid",
            path: "LiquidFluid/Sources/LiquidFluid",
            resources: [.process("Rendering/Fluid.metal")],
            swiftSettings: concurrencySettings + [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "LiquidFluidTests",
            dependencies: ["LiquidFluid"],
            path: "LiquidFluid/Tests/LiquidFluidTests",
            swiftSettings: concurrencySettings + [.defaultIsolation(nil)]
        ),
    ],
    swiftLanguageModes: [.v6]
)

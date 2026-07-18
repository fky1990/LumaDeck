// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LumaDeck",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "LumaDeck", targets: ["LumaDeck"])
    ],
    targets: [
        .executableTarget(
            name: "LumaDeck",
            path: "Sources/LumaDeck",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("ServiceManagement")
            ]
        )
    ],
    swiftLanguageModes: [.v5]
)

// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HingeBluetooth",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "HingeBluetooth", targets: ["HingeBluetooth"])
    ],
    targets: [
        .executableTarget(
            name: "HingeBluetooth",
            path: "Sources/HingeBluetooth",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("IOKit"),
                .linkedFramework("IOBluetooth"),
                .linkedFramework("ServiceManagement")
            ]
        )
    ]
)

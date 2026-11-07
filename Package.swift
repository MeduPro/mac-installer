// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TomatoInstaller",
    defaultLocalization: "de",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "TomatoInstaller", targets: ["TomatoInstaller"]),
        .library(name: "TomatoCore", targets: ["TomatoCore"]),
    ],
    targets: [
        // Installationslogik ohne UI – vollständig testbar.
        .target(name: "TomatoCore"),
        // SwiftUI-Oberfläche; scripts/build-app.sh packt sie in Tomato-Installer.app.
        .executableTarget(name: "TomatoInstaller", dependencies: ["TomatoCore"]),
        .testTarget(name: "TomatoCoreTests", dependencies: ["TomatoCore"]),
    ]
)

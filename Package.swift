// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacInstaller",
    defaultLocalization: "de",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MacInstaller", targets: ["MacInstaller"]),
        .library(name: "MacInstallerCore", targets: ["MacInstallerCore"]),
    ],
    targets: [
        // Installationslogik ohne UI – vollständig testbar.
        .target(name: "MacInstallerCore"),
        // SwiftUI-Oberfläche; scripts/build-app.sh packt sie in „MeduPro Mac-Installer.app“.
        .executableTarget(name: "MacInstaller", dependencies: ["MacInstallerCore"]),
        .testTarget(name: "MacInstallerCoreTests", dependencies: ["MacInstallerCore"]),
    ]
)

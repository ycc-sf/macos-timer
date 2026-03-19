// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacOSReminderApp",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "MacOSReminderApp", targets: ["MacOSReminderApp"])
    ],
    targets: [
        .executableTarget(
            name: "MacOSReminderApp",
            path: "Sources"
        )
    ]
)

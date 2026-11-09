// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "Hyaline",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "Hyaline", targets: ["Hyaline"]),
    ],
    targets: [
        // Everything: widgets, data, the desktop windows and the gallery.
        .target(
            name: "HyalineKit",
            // Testable in every configuration, so hyaline-check builds in release too.
            swiftSettings: [.swiftLanguageMode(.v5), .unsafeFlags(["-enable-testing"])],
            linkerSettings: [
                .linkedFramework("IOKit"), .linkedFramework("CoreWLAN"),
                .linkedFramework("EventKit"), .linkedFramework("CoreLocation"),
            ]
        ),
        // The app: starts HyalineKit.
        .executableTarget(name: "Hyaline", dependencies: ["HyalineKit"], swiftSettings: [.swiftLanguageMode(.v5)]),
        // Command Line Tools ship no XCTest, so the checks are a plain program.
        .executableTarget(name: "hyaline-check", dependencies: ["HyalineKit"], swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)

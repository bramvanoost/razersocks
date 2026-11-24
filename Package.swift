// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "razersocks",
    platforms: [.macOS(.v12)],
    products: [.executable(name: "razersocks", targets: ["razersocks"])],
    targets: [
        .target(
            name: "RazerSocksCore",
            linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("CoreFoundation")]
        ),
        .executableTarget(name: "razersocks", dependencies: ["RazerSocksCore"]),
        .testTarget(name: "RazerSocksCoreTests", dependencies: ["RazerSocksCore"]),
    ]
)

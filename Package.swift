// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Modafinil",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Modafinil", targets: ["Modafinil"]),
        .executable(name: "ModafinilHelper", targets: ["ModafinilHelper"]),
        .executable(name: "Vigil", targets: ["Vigil"]),
        .executable(name: "VigilDaemon", targets: ["VigilDaemon"])
    ],
    targets: [
        .target(
            name: "ModafinilShared"
        ),
        .executableTarget(
            name: "Modafinil",
            dependencies: ["ModafinilShared"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement")
            ]
        ),
        .executableTarget(
            name: "ModafinilHelper",
            dependencies: ["ModafinilShared"]
        ),
        .testTarget(name: "VigilDaemonTests", dependencies: ["VigilDaemon"]),
        .target(
            name: "VigilShared"
        ),
        .executableTarget(
            name: "Vigil",
            dependencies: ["VigilShared"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ServiceManagement")
            ]
        ),
        .executableTarget(
            name: "VigilDaemon",
            dependencies: ["VigilShared"],
            linkerSettings: [
                .linkedFramework("CoreGraphics"),
                .linkedFramework("IOKit")
            ]
        )
    ]
)

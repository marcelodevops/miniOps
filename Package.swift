// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "miniOps",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "miniOps", targets: ["MiniOpsApp"]),
        .executable(name: "miniOpsTests", targets: ["MiniOpsTestRunner"]),
        .library(name: "MiniOpsCore", targets: ["MiniOpsCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.2.0")
    ],
    targets: [
        .target(
            name: "MiniOpsCore",
            dependencies: [
                .product(name: "SwiftTerm", package: "SwiftTerm")
            ]
        ),
        .executableTarget(
            name: "MiniOpsApp",
            dependencies: [
                "MiniOpsCore",
                .product(name: "SwiftTerm", package: "SwiftTerm")
            ]
        ),
        .executableTarget(
            name: "MiniOpsTestRunner",
            dependencies: ["MiniOpsCore"]
        ),
    ]
)

// swift-tools-version:5.3
import PackageDescription

let package = Package(
    name: "convay_hls_player",
    platforms: [
        .iOS("12.0")
    ],
    products: [
        .library(
            name: "convay_hls_player",
            targets: ["convay_hls_player"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "convay_hls_player",
            dependencies: [],
            path: "../Classes"
        )
    ]
)

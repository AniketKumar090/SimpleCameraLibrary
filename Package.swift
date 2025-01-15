// swift-tools-version: 5.5
import PackageDescription

let package = Package(
    name: "SimpleCameraLibrary",
    platforms: [
        .iOS(.v13)  // Set minimum iOS version for your package
    ],
    products: [
        .library(
            name: "SimpleCameraLibrary",
            targets: ["SimpleCameraLibrary"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "SimpleCameraLibrary",
            dependencies: [],
            path: "Sources"  // Ensure you have the correct path for your source files
        ),
    ]
)

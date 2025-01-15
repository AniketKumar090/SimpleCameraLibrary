// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SimpleCameraLibrary",
    platforms: [.iOS(.v13)],
    products: [
        .library(
            name: "SimpleCameraLibrary",
            targets: ["SimpleCameraLibrary"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "SimpleCameraLibrary",
            dependencies: []),
//        .testTarget(
//                    name: "SimpleCameraLibraryTests",
//                    dependencies: ["SimpleCameraLibrary"]),
    ]
)

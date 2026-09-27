// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SignBridge",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
    ],
    products: [
        .library(name: "SignCore", targets: ["SignCore"]),
        .executable(name: "signbridged", targets: ["signbridged"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-asn1.git", from: "1.2.0"),
        .package(url: "https://github.com/apple/swift-certificates.git", from: "1.5.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "4.5.1"),
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.0"),
    ],
    targets: [
        .systemLibrary(name: "Clibxml2", path: "Sources/Clibxml2"),
        .target(
            name: "SignCore",
            dependencies: [
                "Clibxml2",
                .product(name: "SwiftASN1", package: "swift-asn1"),
                .product(name: "X509", package: "swift-certificates"),
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
            ]
        ),
        .executableTarget(
            name: "signbridged",
            dependencies: ["SignCore"]
        ),
        .testTarget(
            name: "SignCoreTests",
            dependencies: [
                "SignCore",
                .product(name: "X509", package: "swift-certificates"),
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "_CryptoExtras", package: "swift-crypto"),
            ],
            resources: [.copy("Resources/sample.udf")]
        ),
    ]
)

// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MailJay",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MailJay", targets: ["MailJay"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle.git", exact: "2.9.3"),
    ],
    targets: [
        .executableTarget(
            name: "MailJay",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/MailJay",
            exclude: [
                "Resources/AppIcon.icns"
            ],
            resources: [
                .copy("Resources/Onboarding")
            ]
        ),
        .testTarget(
            name: "MailJayTests",
            dependencies: ["MailJay"]
        )
    ],
    swiftLanguageModes: [.v5]
)

// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MailJay",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MailJay", targets: ["MailJay"])
    ],
    targets: [
        .executableTarget(
            name: "MailJay",
            path: "Sources/MailJay",
            exclude: [
                "Resources/AppIcon.icns",
                "Resources/__pycache__"
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

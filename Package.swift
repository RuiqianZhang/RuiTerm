// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "RuiTerm",
    platforms: [
        .custom("macos", versionString: "26.0")
    ],
    dependencies: [
        .package(url: "https://github.com/mchakravarty/CodeEditorView.git", from: "0.15.4")
    ],
    targets: [
        .target(
            name: "SwiftTerm",
            path: "Vendor/SwiftTerm/Sources/SwiftTerm",
            exclude: ["iOS", "Documentation.docc", "Mac/README.md"],
            resources: [.process("Apple/Metal/Shaders.metal")]
        ),
        .executableTarget(
            name: "RuiTerm",
            dependencies: [
                "SwiftTerm",
                "CodeEditorView"
            ],
            path: "Sources/RuiTerm"
        )
    ],
    swiftLanguageVersions: [.v5]
)

// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "SubscriptionKit",
    platforms: [.macOS(.v14)],
    products: [.library(name: "SubscriptionKit", targets: ["SubscriptionKit"])],
    dependencies: [.package(url: "https://github.com/jpsim/Yams.git", exact: "5.1.3")],
    targets: [
        .target(name: "SubscriptionKit", dependencies: ["Yams"]),
        .testTarget(name: "SubscriptionKitTests", dependencies: ["SubscriptionKit"])
    ]
)

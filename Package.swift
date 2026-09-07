// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Pomodoro",
    platforms: [
        .macOS(.v26)
    ],
    targets: [
        .target(
            name: "PomodoroCore"
        ),
        .executableTarget(
            name: "Pomodoro",
            dependencies: ["PomodoroCore"]
        ),
        .executableTarget(
            name: "PomodoroChecks",
            dependencies: ["PomodoroCore"]
        ),
    ]
)

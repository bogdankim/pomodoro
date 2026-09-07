<div align="center">
  <img src="Resources/AppIcon.png" width="128" alt="Pomodoro app icon">
</div>

# Pomodoro

A pomodoro timer that lives in the macOS menu bar, with a task list and quick-add from anywhere. Built with SwiftUI on the macOS 26 SDK, and the interface uses the system Liquid Glass material. There is no Dock icon and no main window.

During a focus session the ring starts full and drains; breaks fill it back up. A long break follows every N focus sessions (4 by default). When a timer ends, a chime plays and a summary shows what you completed and what is still open.

## Requirements

- macOS 26 or later to run
- Command Line Tools with the macOS 26.1 SDK (or full Xcode) to build

## Build and run

```sh
./Scripts/make_app.sh release
open build/Pomodoro.app
```

The script builds with Swift Package Manager and assembles `build/Pomodoro.app` with an `LSUIElement` Info.plist, the app icon, and an ad-hoc signature.

To run the logic checks:

```sh
swift run PomodoroChecks
```

## Usage

| Action | How |
| --- | --- |
| Open the panel | Click the timer icon in the menu bar |
| Start / pause | Primary button |
| Skip a phase | Skip button; a skipped focus does not count toward the long break |
| Restart the loop | Reset button; clears cycle progress too |
| Add a task in the panel | Type in the field, press Return; Tab cycles the priority |
| Quick-add from anywhere | ⌘⇧P, type, Tab for priority, Return to create |
| Complete a task | Click the circle to its left |
| Undo within five seconds | Click the checkmark again |
| Delete a task | Hover the row and click the x, or use the context menu |
| Settings | Gear button in the panel footer |
| Quit | Power button in the panel footer |

⌘⇧P opens the menu bar panel with the input focused by default; a standalone floating panel is available in Settings. Durations, the long-break interval, auto-start, the chime, the menu bar icon style (ring, time, or both), and open-at-login are all configurable in Settings, and every duration accepts typed input.

Tasks persist to `~/Library/Application Support/Pomodoro/tasks.json`; settings live in `UserDefaults`.

## Project layout

```
Sources/PomodoroCore      Timer engine, task model, formatting (no UI, checked by PomodoroChecks)
Sources/Pomodoro          App entry, models, views, panels, status item, AppKit plumbing
Sources/PomodoroChecks    Assertion-harness checks for the core
Scripts/make_app.sh       Bundle assembly and codesigning
Scripts/make_icon.swift   App icon renderer
Resources                 Info.plist, AppIcon.icns
```

## Design notes

The interface follows the Apple Human Interface Guidelines and the Liquid Glass adoption guidance: stock components first, glass only on the two floating panels, a monochrome menu bar icon drawn as a template image, semantic system colors, SF Symbols with accessibility labels, and Reduce Motion support. Priority colors match the Reminders convention (blue, orange, red), and the focus phase uses orange like the Apple Timer app.

## Regenerating the icon

```sh
swift Scripts/make_icon.swift
iconutil -c icns build/icon.iconset -o Resources/AppIcon.icns
```

## License

[MIT](LICENSE)


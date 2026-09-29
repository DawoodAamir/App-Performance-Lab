# Contributing

Open an issue describing the observed behavior, expected result, device, OS, and reproduction steps. Exclude client details, sensor identifiers, credentials, and private exports from reports.

Keep platform-independent rules in `Sources/Core` and UI/framework code in `Sources/App`. Add behavior tests for parsing, persistence formats, and boundary conditions when changing them. Preserve the iOS 15 target unless a feature requires a documented change.

Run `swift test` and build the Xcode scheme before opening a pull request. Review VoiceOver labels, larger text, dark mode, landscape, and iPad layouts for UI changes. Device-only behavior needs device verification.

Use concise Conventional Commits, such as `fix: reject truncated sensor packets` or `feat: add result filtering`. Follow the included `.swift-format` configuration; run `xcrun swift-format format -i -r Sources Tests` when available.

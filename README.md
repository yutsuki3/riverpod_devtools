# Riverpod DevTools

[![pub package](https://img.shields.io/pub/v/riverpod_devtools.svg)](https://pub.dev/packages/riverpod_devtools)

A [DevTools](https://flutter.dev/devtools) extension for [Riverpod](https://riverpod.dev) - inspect and monitor your providers in real-time.

<img src="https://raw.githubusercontent.com/yutsuki3/riverpod_devtools/main/packages/riverpod_devtools/example/screenshot_inspector.png" width="100%" alt="Riverpod DevTools Demo" />

## 📦 Packages

This repository contains the following packages:

| Package | Version | Description |
|---------|---------|-------------|
| [riverpod_devtools](./packages/riverpod_devtools) | [![pub](https://img.shields.io/pub/v/riverpod_devtools.svg)](https://pub.dev/packages/riverpod_devtools) | DevTools extension for Riverpod (bundles an optional MCP server) |

## 🚀 Quick Start

For end-users who want to use this package in their Flutter app, please see the [package README](./packages/riverpod_devtools/README.md) or visit [pub.dev](https://pub.dev/packages/riverpod_devtools).

```bash
flutter pub add riverpod_devtools
```

## 🤖 Optional: AI Tool Integration via MCP

`riverpod_devtools` bundles an optional MCP server that lets AI tools like Claude Code read live Riverpod provider state — event logs, current values, the dependency graph, and health stats — from your running Flutter app, and drive it (invalidate/refresh a provider, or set its value). So you can ask things like "look at the current provider logs and fix any behavior that differs from the spec."

See [packages/riverpod_devtools/MCP.md](./packages/riverpod_devtools/MCP.md) for setup instructions.

## 🛠️ Development

This section is for contributors who want to develop or modify this package.

### Prerequisites

- Flutter SDK (>=3.32.0)
- Dart SDK (>=3.7.0)

> **Note:** As of 0.6.0, these minimums were raised to accommodate the bundled MCP server's `dart_mcp` dependency. See [Version Compatibility](#-version-compatibility).

### Repository Structure

```
riverpod_devtools/
├── packages/
│   ├── riverpod_devtools/           # Main package (published to pub.dev)
│   │   ├── lib/                     # Package source code (includes lib/src/mcp/)
│   │   ├── bin/                     # Executables: analyze, riverpod_devtools_mcp
│   │   ├── test/                    # Unit tests
│   │   ├── extension/devtools/      # Built DevTools extension UI
│   │   ├── example/                 # Example app
│   │   └── MCP.md                   # Optional MCP server setup guide
│   └── riverpod_devtools_extension/ # DevTools extension source (Flutter web app)
│       ├── lib/                     # Extension UI source code
│       └── web/                     # Web assets
├── example/                         # Standalone example app
└── README.md                        # This file
```

### Getting Started with Development

1. Clone the repository:
   ```bash
   git clone https://github.com/yutsuki3/riverpod_devtools.git
   cd riverpod_devtools
   ```

2. Install dependencies for the main package:
   ```bash
   cd packages/riverpod_devtools
   flutter pub get
   ```

3. Run tests:
   ```bash
   flutter test
   ```

4. Run the example app:
   ```bash
   # From the repository root
   cd example
   flutter run

   # Or use the package's example
   cd packages/riverpod_devtools/example
   flutter run
   ```

### Building the DevTools Extension

The DevTools extension UI is a Flutter web app that needs to be built separately:

```bash
# From the repository root
cd packages/riverpod_devtools_extension
flutter pub get
flutter build web --release

# The built files need to be copied to the main package
# (This is typically done automatically by the build script)
```

**Note:** The built extension is included in `packages/riverpod_devtools/extension/devtools/build/` and published with the package.

### Running Tests

```bash
# Run all tests
cd packages/riverpod_devtools
flutter test

# Run with coverage
flutter test --coverage
```

### Code Quality

```bash
# Run analyzer
flutter analyze

# Format code
dart format .
```

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

### Contribution Guidelines

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

### Reporting Issues

Please use the [GitHub issue tracker](https://github.com/yutsuki3/riverpod_devtools/issues) to report bugs or request features.

## 📝 Version Compatibility

| riverpod_devtools | flutter_riverpod | Flutter  |
|-------------------|------------------|----------|
| 1.1.x             | >=2.3.0 <4.0.0   | >=3.32.0 |
| 1.0.x             | >=2.3.0 <4.0.0   | >=3.32.0 |
| 0.6.x             | >=2.3.0 <4.0.0   | >=3.32.0 |
| 0.5.x             | >=2.3.0 <4.0.0   | >=3.0.0  |
| 0.4.x             | >=2.3.0 <4.0.0   | >=3.0.0  |
| 0.3.x             | >=2.6.1 <4.0.0   | >=3.0.0  |
| 0.2.x             | >=2.6.1 <4.0.0   | >=3.0.0  |
| 0.1.x             | ^2.6.1           | >=3.0.0  |

> **0.6.0** raised the minimum Flutter/Dart SDK to support the bundled MCP server (`dart_mcp` requires a newer `async` than older Flutter SDKs ship). If you can't upgrade yet, pin `riverpod_devtools: ^0.5.0`.

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🔗 Links

- **Package**: [pub.dev/packages/riverpod_devtools](https://pub.dev/packages/riverpod_devtools)
- **Repository**: [github.com/yutsuki3/riverpod_devtools](https://github.com/yutsuki3/riverpod_devtools)
- **Issues**: [github.com/yutsuki3/riverpod_devtools/issues](https://github.com/yutsuki3/riverpod_devtools/issues)
- **Riverpod**: [riverpod.dev](https://riverpod.dev)

## 🙏 Acknowledgments

- Thanks to the [Riverpod](https://github.com/rrousselGit/riverpod) team for creating an amazing state management solution
- Inspired by the official [Flutter DevTools](https://flutter.dev/devtools)

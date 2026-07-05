# riverpod_devtools

[![pub package](https://img.shields.io/pub/v/riverpod_devtools.svg)](https://pub.dev/packages/riverpod_devtools)
[![MCP](https://img.shields.io/badge/MCP-supported-blue)](https://modelcontextprotocol.io/)

A [DevTools](https://flutter.dev/devtools) extension for [Riverpod](https://riverpod.dev) - inspect and monitor your providers in real-time. **Now meets [MCP](https://modelcontextprotocol.io/)**, so AI coding tools can read that same live provider state too.

<img src="https://raw.githubusercontent.com/yutsuki3/riverpod_devtools/main/packages/riverpod_devtools/example/screenshot_044.png" width="100%" alt="Riverpod DevTools Demo" />

## Features

- **AI Tool Integration (MCP)**: Let AI coding tools like Claude Code read live provider event logs via an optional bundled MCP server.
- **Static Dependency Analysis**: Accurate provider dependency detection using CLI-based code analysis.
- **Provider Graph**: Visualize the relationships between your providers with precise dependency data.
- **State Inspector**: View the current state of your providers with type labels and optimized display.
- **Event Log**: Track provider lifecycle events with hierarchical grouping and sub-events.
- **Light Mode Support**: Seamlessly switch between light and dark themes.

## 🤖 riverpod_devtools meets MCP

Your AI coding tool normally only sees your source code — not what's actually happening while your app runs. This package bundles an optional [MCP](https://modelcontextprotocol.io/) server so tools like Claude Code can read **live** Riverpod provider event logs straight from your running app, and act on them:

> "Look at the current provider logs and fix any behavior that differs from the spec."

See [MCP.md](MCP.md) for setup — it takes one `.mcp.json` entry.

## Getting started

1.  Add `riverpod_devtools` to your `pubspec.yaml`:

    Run the command:

    ```bash
    flutter pub add riverpod_devtools
    ```

    Or manually add it:

    ```yaml
    dependencies:
      riverpod_devtools: ^0.5.0
      flutter_riverpod: '>=2.3.0 <4.0.0'
    ```

    **Note:** This package supports both Riverpod 2.x and 3.x.

2.  Add `RiverpodDevToolsObserver` to your `ProviderScope` and load static dependencies:

    While the DevTools extension is automatically detected, you **must** add the observer to enable communication between your app and the DevTools.

    ```dart
    import 'package:flutter/material.dart';
    import 'package:flutter/services.dart' show rootBundle;
    import 'package:flutter_riverpod/flutter_riverpod.dart';
    import 'package:riverpod_devtools/riverpod_devtools.dart';

    void main() async {
      WidgetsFlutterBinding.ensureInitialized();

      // Load static dependencies (required for dependency graph)
      try {
        final jsonString = await rootBundle.loadString(
          'lib/riverpod_dependencies.json',
        );
        RiverpodDevToolsRegistry.instance.loadFromJson(jsonString);
      } catch (_) {
        // DevTools will show setup instructions if JSON is not available
      }

      runApp(
        ProviderScope(
          observers: [RiverpodDevToolsObserver()],
          child: const MyApp(),
        ),
      );
    }
    ```

3.  Declare the generated JSON in `pubspec.yaml`:

    ```yaml
    flutter:
      assets:
        - lib/riverpod_dependencies.json
    ```

## Usage

1.  Run your Flutter app.
2.  Open Flutter DevTools (use the link printed in the terminal).
3.  Look for the **"riverpod_devtools"** tab in DevTools.
4.  Interact with your app and watch the events and state updates in the DevTools tab.

## Static Dependency Analysis (Required for Dependency Graph)

**Important**: To enable the dependency graph feature, you must run the CLI tool to analyze your providers. This provides:

- **Accurate dependency detection** from source code (AST-based)
- **Dependency type identification** (watch/read/listen)
- **Source code location tracking** (file, line, column)
- **No heuristic false positives** from timing-based detection

### Setup

1. Run the analyzer to generate dependency metadata:

   ```bash
   # One-time generation
   dart run riverpod_devtools:analyze

   # Watch mode (recommended during development)
   dart run riverpod_devtools:analyze --watch
   ```

   This will create a `lib/riverpod_dependencies.json` file with all your provider dependencies.

2. Load the generated JSON in your `main()` (see Getting started above).

3. Add the JSON file to your app assets in `pubspec.yaml`.

### DevTools UI states

The Provider Details panel shows one of the following for dependencies:

- **Depends On / Used By**: Static analysis loaded and the provider name matches the JSON entry.
- **Provider Name Mismatch**: JSON is loaded, but the runtime provider name does not exactly match any entry (case-sensitive).
- **Static Analysis Required**: JSON was not loaded — run the analyzer and configure `main()` as shown above.

### Benefits

- **Static analysis**: Dependencies detected from AST at build time
- **Minimal code changes**: Only need to modify `main.dart` and `pubspec.yaml` assets — no `part` directives needed
- **Clear setup guidance**: DevTools UI shows collapsible instructions when setup is incomplete

## Migration from 0.4.x

Version 0.5.0 removes runtime-based dependency detection. If you relied on dependencies appearing without running the analyzer:

1. Run `dart run riverpod_devtools:analyze`
2. Load `lib/riverpod_dependencies.json` via `RiverpodDevToolsRegistry.instance.loadFromJson()`
3. Add the JSON file to your `pubspec.yaml` assets

Event log and state inspection continue to work with only `RiverpodDevToolsObserver()` — the dependency graph requires static analysis.

## Additional information

-   **Repository**: [https://github.com/yutsuki3/riverpod_devtools](https://github.com/yutsuki3/riverpod_devtools)
-   **Issues**: [https://github.com/yutsuki3/riverpod_devtools/issues](https://github.com/yutsuki3/riverpod_devtools/issues)
-   **Troubleshooting**: [TROUBLESHOOTING.md](TROUBLESHOOTING.md)

Contributions are welcome!

## License

This package is released under the MIT License. See [LICENSE](LICENSE) for details.

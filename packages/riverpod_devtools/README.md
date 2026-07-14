# riverpod_devtools

[![pub package](https://img.shields.io/pub/v/riverpod_devtools.svg)](https://pub.dev/packages/riverpod_devtools)
[![MCP](https://img.shields.io/badge/MCP-supported-blue)](https://modelcontextprotocol.io/)

A [DevTools](https://flutter.dev/devtools) extension for [Riverpod](https://riverpod.dev) - inspect and monitor your providers in real-time. **Now meets [MCP](https://modelcontextprotocol.io/)**, so AI coding tools can read that same live provider state too.

<img src="https://raw.githubusercontent.com/yutsuki3/riverpod_devtools/main/packages/riverpod_devtools/example/screenshot_inspector.png" width="100%" alt="Riverpod DevTools — provider inspector with live state and event log" />

## Features

- **AI Tool Integration (MCP)**: Let AI coding tools like Claude Code read live provider state, event logs, the dependency graph, and health stats — and drive state (invalidate/refresh a provider, or set its value) — via an optional bundled MCP server. See [MCP.md](MCP.md).
- **Provider Graph**: Interactive dependency graph — `watch`/`read`/`listen` edges, dependency-cycle highlighting, and click-to-focus with pan/zoom — built from precise static analysis.
- **State Inspector**: View the current state of your providers with type labels and optimized display, and invalidate/refresh them from the panel.
- **Performance Stats**: Per-provider update rate (with sparkline), async load duration, and dispose→re-create churn, with warning badges for hot or slow providers.
- **Event Log**: Track provider lifecycle events with hierarchical grouping, sub-events, and value diffs.
- **Static Dependency Analysis**: Accurate provider dependency detection using CLI-based code analysis.
- **Light & Dark themes**: Seamlessly switch between light and dark modes.

## Screenshots

**Dependency Graph** — an interactive graph of `watch`/`read`/`listen` edges with runtime status colors, cycle highlighting, and click-to-focus:

<img src="https://raw.githubusercontent.com/yutsuki3/riverpod_devtools/main/packages/riverpod_devtools/example/screenshot_graph.png" width="100%" alt="Riverpod DevTools dependency graph" />

**Performance Stats** — per-provider update rate, async load time, and dispose→re-create churn, with hot/slow providers flagged:

<img src="https://raw.githubusercontent.com/yutsuki3/riverpod_devtools/main/packages/riverpod_devtools/example/screenshot_stats.png" width="100%" alt="Riverpod DevTools Performance Stats" />

## 🤖 riverpod_devtools meets MCP

Your AI coding tool normally only sees your source code — not what's actually happening while your app runs. This package bundles an optional [MCP](https://modelcontextprotocol.io/) server so tools like Claude Code can read **live** Riverpod state straight from your running app, and act on it:

> "Look at the current provider logs and fix any behavior that differs from the spec."

The AI can inspect provider event logs, current state, the dependency graph, and per-provider health stats, and can drive state — invalidate/refresh a provider, or set it to a specific value to reproduce an edge case. Responses are compact by default to stay token-efficient.

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
      riverpod_devtools: ^1.0.0
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
      } catch (e) {
        // The asset is missing or unreadable. Log the reason instead of
        // swallowing it silently — otherwise the dependency graph is just
        // empty with no hint as to why.
        debugPrint('riverpod_devtools: could not load dependency data: $e');
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

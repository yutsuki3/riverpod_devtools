# riverpod_devtools

[![pub package](https://img.shields.io/pub/v/riverpod_devtools.svg)](https://pub.dev/packages/riverpod_devtools)

A [DevTools](https://flutter.dev/devtools) extension for [Riverpod](https://riverpod.dev) - inspect and monitor your providers in real-time.

<img src="https://raw.githubusercontent.com/yutsuki3/riverpod_devtools/main/packages/riverpod_devtools/example/screenshot_044.png" width="100%" alt="Riverpod DevTools Demo" />

## Features

- **Static Dependency Analysis**: Accurate provider dependency detection using CLI-based code analysis.
- **Provider Graph**: Visualize the relationships between your providers with precise dependency data.
- **State Inspector**: View the current state of your providers with type labels and optimized display.
- **Event Log**: Track provider lifecycle events with hierarchical grouping and sub-events.
- **Light Mode Support**: Seamlessly switch between light and dark themes.

## Getting started

1.  Add `riverpod_devtools` to your `pubspec.yaml`:

    Run the command:

    ```bash
    flutter pub add riverpod_devtools
    ```

    Or manually add it:

    ```yaml
    dependencies:
      riverpod_devtools: ^0.4.4
      flutter_riverpod: '>=2.3.0 <4.0.0'
    ```

    **Note:** This package supports both Riverpod 2.x and 3.x.

2.  Add `RiverpodDevToolsObserver` to your `ProviderScope`:

    While the DevTools extension is automatically detected, you **must** add the observer to enable communication between your app and the DevTools.

    ```dart
    import 'package:flutter_riverpod/flutter_riverpod.dart';
    import 'package:riverpod_devtools/riverpod_devtools.dart';

    void main() {
      runApp(
        ProviderScope(
          observers: [
            RiverpodDevToolsObserver(),
          ],
          child: MyApp(),
        ),
      );
    }
    ```

## Usage

1.  Run your Flutter app.
2.  Open semantic DevTools (open the debugger).
3.  Look for the "riverpod_devtools" tab in DevTools.
4.  Interact with your app and watch the events and state updates in the DevTools tab.

## Static Dependency Analysis (Required for Dependency Graph)

**Important**: To enable the dependency graph feature, you must run the CLI tool to analyze your providers. This provides:

- **100% accurate dependency detection** from source code
- **Dependency type identification** (watch/read/listen)
- **Source code location tracking** (file, line, column)
- **No false positives** from heuristic-based detection

### Setup

1. Run the analyzer to generate dependency metadata:

   ```bash
   # One-time generation
   dart run riverpod_devtools:analyze

   # Watch mode (recommended during development)
   dart run riverpod_devtools:analyze --watch
   ```

   This will create a `lib/riverpod_dependencies.json` file with all your provider dependencies.

2. Load the generated JSON in your `main()`:

   ```dart
   import 'package:flutter/services.dart' show rootBundle;
   import 'package:riverpod_devtools/riverpod_devtools.dart';

   void main() async {
     WidgetsFlutterBinding.ensureInitialized();

     // Load static dependencies
     final jsonString = await rootBundle.loadString(
       'lib/riverpod_dependencies.json',
     );
     RiverpodDevToolsRegistry.instance.loadFromJson(jsonString);

     runApp(
       ProviderScope(
         observers: [RiverpodDevToolsObserver()],
         child: MyApp(),
       ),
     );
   }
   ```

### Benefits

- **Static analysis**: Dependencies detected from AST at build time
- **Hybrid approach**: Falls back to runtime detection for dynamic providers
- **Backward compatible**: Works without running the analyzer (runtime detection only)
- **Visual indicators**: DevTools UI shows whether dependencies are from static or runtime analysis
- **Minimal code changes**: Only need to modify `main.dart` - no `part` directives needed

## Additional information

-   **Repository**: [https://github.com/yutsuki3/riverpod_devtools](https://github.com/yutsuki3/riverpod_devtools)
-   **Issues**: [https://github.com/yutsuki3/riverpod_devtools/issues](https://github.com/yutsuki3/riverpod_devtools/issues)

Contributions are welcome!

## License

This package is released under the MIT License. See [LICENSE](LICENSE) for details.

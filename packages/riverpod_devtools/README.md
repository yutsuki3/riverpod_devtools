# riverpod_devtools

[![pub package](https://img.shields.io/pub/v/riverpod_devtools.svg)](https://pub.dev/packages/riverpod_devtools)

A [DevTools](https://flutter.dev/devtools) extension for [Riverpod](https://riverpod.dev) - inspect and monitor your providers in real-time.

<img src="https://raw.githubusercontent.com/yutsuki3/riverpod_devtools/main/packages/riverpod_devtools/example/screenshot_040.png" width="100%" alt="Riverpod DevTools Demo" />

## Features

- **Provider Graph**: Visualize the relationships between your providers (Beta: Learning-based tracking).
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
      riverpod_devtools: ^0.4.2
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

## Additional information

-   **Repository**: [https://github.com/yutsuki3/riverpod_devtools](https://github.com/yutsuki3/riverpod_devtools)
-   **Issues**: [https://github.com/yutsuki3/riverpod_devtools/issues](https://github.com/yutsuki3/riverpod_devtools/issues)

Contributions are welcome!

## License

This package is released under the MIT License. See [LICENSE](LICENSE) for details.

# riverpod_devtools

A [DevTools](https://flutter.dev/devtools) extension for [Riverpod](https://riverpod.dev) - inspect and monitor your providers in real-time.

<img src="https://raw.githubusercontent.com/yutsuki3/riverpod_devtools/main/packages/riverpod_devtools/example/demo.gif" width="100%" alt="Riverpod DevTools Demo" />

## Features

- **Provider Graph**: Visualize the relationships between your providers correctly (Coming soon!).
- **State Inspector**: View the current state of your providers.
- **Event Log**: Track provider lifecycle events (add, update, dispose).
- **History Tracking**: Jump back in time to see previous states.

## Getting started

1.  Add `riverpod_devtools` to your `pubspec.yaml`:

    ```yaml
    dependencies:
      riverpod_devtools: ^0.1.0
      flutter_riverpod: ^2.6.1 # or compatible version
    ```

    **Note:** This package is currently in early development.

2.  Wrap your `ProviderScope` with `RiverpodDevToolsObserver` (if manual setup is needed, though future versions might automate this via `riverpod_generator` or similar hooks).

    Currently, you just need to install the package. The DevTools extension will automatically be detected by Flutter DevTools.

    *To enable logging in the extension, add the observer:*

    ```dart
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

    *Import:*
    ```dart
    import 'package:riverpod_devtools/riverpod_devtools.dart';
    ```

## Usage

1.  Run your Flutter app.
2.  Open semantic DevTools (open the debugger).
3.  Look for the "Riverpod" tab in DevTools.
4.  Interact with your app and watch the events and state updates in the DevTools tab.

## Additional information

-   **Repository**: [https://github.com/yutsuki3/riverpod_devtools](https://github.com/yutsuki3/riverpod_devtools)
-   **Issues**: [https://github.com/yutsuki3/riverpod_devtools/issues](https://github.com/yutsuki3/riverpod_devtools/issues)

Contributions are welcome!

## License

This package is released under the MIT License. See [LICENSE](LICENSE) for details.
